package local.keypocket.android;

import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Context;
import android.os.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.*;

@SuppressWarnings("deprecation")
final class BluetoothDoorClient {
    private final Context context;
    private final Handler main=new Handler(Looper.getMainLooper());
    private volatile Attempt active;
    BluetoothDoorClient(Context context){this.context=context.getApplicationContext();}
    static UUID uuid(String shortID){return UUID.fromString("0000"+shortID+"-0000-1000-8000-00805f9b34fb");}
    static final UUID SERVICE=uuid("ffc0"),CHALLENGE=uuid("ffc1"),AUTH=uuid("ffc2"),COMMAND=uuid("ffc3");
    private static class Failure extends Exception {final boolean retry;Failure(String text,boolean retry){super(text);this.retry=retry;}}
    void open(Door door,LongSupplier clock,BooleanSupplier cancelled,Consumer<String> status)throws Exception {
        for(int i=0;i<2;i++) {
            if(cancelled.getAsBoolean())throw new InterruptedException("已取消");door.validate(clock.getAsLong(),false);
            Attempt a=new Attempt(door,clock,status);active=a;
            main.post(()->{if(cancelled.getAsBoolean())a.finish("已取消",false);else a.start();});
            try {a.result.get();return;}
            catch(ExecutionException e){Throwable cause=e.getCause();if(i==0&&cause instanceof Failure&&((Failure)cause).retry&&!cancelled.getAsBoolean()){status.accept("尚未发送开门数据，正在重试一次…");Thread.sleep(250);}else throw cause instanceof Exception?(Exception)cause:new Exception(cause);}
            catch(InterruptedException e){main.post(()->a.finish("已取消",false));throw e;}
            finally{if(active==a)active=null;}
        }
    }
    void cancel(){Attempt a=active;if(a!=null)main.post(()->a.finish("已取消",false));}
    final class Attempt {
        final Door door;final LongSupplier clock;final Consumer<String> status;final CompletableFuture<Void> result=new CompletableFuture<>();
        BluetoothAdapter adapter;BluetoothLeScanner scanner;BluetoothGatt gatt;BluetoothGattCharacteristic command;
        String phase="idle";byte[] token,payload;int offset;boolean commandStarted=false;
        final Runnable timeout=()->finish("蓝牙开门超时，请靠近门禁重试",true);
        Attempt(Door d,LongSupplier c,Consumer<String> s){door=d;clock=c;status=s;}
        boolean current(BluetoothGatt g){return !result.isDone()&&gatt==g;}
        void start(){
            try{BluetoothManager manager=context.getSystemService(BluetoothManager.class);adapter=manager==null?null:manager.getAdapter();
                if(adapter==null||!adapter.isEnabled()){finish("请先打开蓝牙",false);return;}
                scanner=adapter.getBluetoothLeScanner();if(scanner==null){finish("蓝牙扫描暂不可用",false);return;}
                phase="scanning";status.accept("正在寻找所选门禁…");main.postDelayed(timeout,8000);
                scanner.startScan(null,new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scan);
            }catch(Exception e){finish("无法使用蓝牙，请检查附近设备权限",false);}
        }
        final ScanCallback scan=new ScanCallback(){
            @Override public void onScanResult(int type,ScanResult r){main.post(()->{
                if(result.isDone()||!phase.equals("scanning")||r.getRssi()<=-85||r.getRssi()>=0)return;
                try{String name=r.getScanRecord()==null?null:r.getScanRecord().getDeviceName();if(name==null)name=r.getDevice().getName();
                    if(!Protocol.matches(name,door))return;scanner.stopScan(this);phase="connecting";status.accept("正在连接所选门禁…");
                    gatt=r.getDevice().connectGatt(context,false,callback,BluetoothDevice.TRANSPORT_LE);if(gatt==null)finish("无法连接门禁",true);
                }catch(Exception e){finish("蓝牙连接失败，请检查权限",false);}
            });}
            @Override public void onScanFailed(int code){main.post(()->finish("蓝牙扫描失败（"+code+"），请稍后重试",false));}
        };
        final BluetoothGattCallback callback=new BluetoothGattCallback(){
            @Override public void onConnectionStateChange(BluetoothGatt g,int statusCode,int state){main.post(()->{
                if(!current(g))return;
                if(state==BluetoothProfile.STATE_DISCONNECTED){finish(phase.equals("finishing")?null:"门禁连接中断，未确认请求发送完成",true);return;}
                if(statusCode!=BluetoothGatt.GATT_SUCCESS){finish("门禁连接失败（"+statusCode+"）",true);return;}
                if(state==BluetoothProfile.STATE_CONNECTED&&phase.equals("connecting")){
                    phase="discovering";status.accept("正在验证门禁…");
                    g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                    main.postDelayed(()->{if(current(g)&&phase.equals("discovering")&&!g.discoverServices())finish("无法发现门禁服务",true);},150);
                }
            });}
            @Override public void onServicesDiscovered(BluetoothGatt g,int code){main.post(()->{
                if(!current(g)||!phase.equals("discovering"))return;
                if(code!=0){finish("发现门禁服务失败",true);return;}
                BluetoothGattService s=g.getService(SERVICE);BluetoothGattCharacteristic challenge=s==null?null:s.getCharacteristic(CHALLENGE),auth=s==null?null:s.getCharacteristic(AUTH);command=s==null?null:s.getCharacteristic(COMMAND);
                if(challenge==null||auth==null||command==null||(challenge.getProperties()&BluetoothGattCharacteristic.PROPERTY_READ)==0||(auth.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE)==0||(command.getProperties()&BluetoothGattCharacteristic.PROPERTY_WRITE)==0){finish("此门禁未提供兼容的蓝牙服务",false);return;}
                phase="reading";if(!g.readCharacteristic(challenge))finish("无法读取门禁挑战",true);
            });}
            @Override public void onCharacteristicRead(BluetoothGatt g,BluetoothGattCharacteristic c,int code){byte[] value=c.getValue();read(g,c,value==null?null:value.clone(),code);}
            @Override public void onCharacteristicRead(BluetoothGatt g,BluetoothGattCharacteristic c,byte[] value,int code){read(g,c,value.clone(),code);}
            private void read(BluetoothGatt g,BluetoothGattCharacteristic c,byte[] data,int code){main.post(()->{
                if(!current(g)||!phase.equals("reading")||!c.getUuid().equals(CHALLENGE))return;
                if(code!=0||data==null){finish("读取门禁挑战失败",true);return;}
                try{byte[][] pair=Protocol.challenge(data);token=pair[0];phase="authenticating";
                    if(!write(g.getService(SERVICE).getCharacteristic(AUTH),pair[1]))finish("无法发送门禁验证",true);
                }catch(Exception e){finish(e.getMessage()==null?"门禁协议处理失败":e.getMessage(),false);}
            });}
            @Override public void onCharacteristicWrite(BluetoothGatt g,BluetoothGattCharacteristic c,int code){main.post(()->{
                if(!current(g))return;if(code!=0){finish("蓝牙写入失败，未确认开门请求完成",true);return;}
                try{if(phase.equals("authenticating")&&c.getUuid().equals(AUTH)){
                        payload=Protocol.payload(door,clock.getAsLong(),token);offset=0;phase="writing";status.accept("正在发送开门请求…");sendNext(30);
                    }else if(phase.equals("writing")&&c.getUuid().equals(COMMAND)){
                        if(offset>=payload.length){phase="finishing";main.postDelayed(()->{if(current(g)&&phase.equals("finishing"))finish(null,false);},150);}else sendNext(20);
                    }
                }catch(Exception e){finish(e.getMessage()==null?"门禁协议处理失败":e.getMessage(),false);}
            });}
        };
        boolean write(BluetoothGattCharacteristic c,byte[] data){
            if(Build.VERSION.SDK_INT>=33)return gatt.writeCharacteristic(c,data,BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)==BluetoothStatusCodes.SUCCESS;
            c.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);c.setValue(data);return gatt.writeCharacteristic(c);
        }
        void sendNext(long delay){main.postDelayed(()->{
            if(result.isDone()||!phase.equals("writing"))return;
            try{byte[] chunk=Arrays.copyOfRange(payload,offset,Math.min(offset+20,payload.length));offset+=chunk.length;
                commandStarted=true;if(!write(command,chunk))finish("开门数据未确认发送完成，请检查门的状态",false);
            }catch(Exception e){finish("开门数据未确认发送完成，请检查门的状态",false);}
        },delay);}
        void finish(String error,boolean retryable){
            if(result.isDone())return;boolean retry=retryable&&!commandStarted;
            phase="done";main.removeCallbacks(timeout);
            try{if(scanner!=null)scanner.stopScan(scan);}catch(Exception ignored){}
            BluetoothGatt old=gatt;gatt=null;if(old!=null){try{old.disconnect();}catch(Exception ignored){}try{old.close();}catch(Exception ignored){}}
            token=null;payload=null;
            if(error==null)result.complete(null);else result.completeExceptionally(new Failure(error,retry));
        }
    }
}
