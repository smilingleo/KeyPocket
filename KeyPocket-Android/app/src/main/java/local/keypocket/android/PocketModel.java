package local.keypocket.android;

import android.content.*;
import android.os.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

final class PocketModel {
    private static PocketModel instance;
    static synchronized PocketModel get(Context c){if(instance==null)instance=new PocketModel(c.getApplicationContext());return instance;}
    final Context context;final SharedPreferences settings;final SecureStore secure;
    final BluetoothDoorClient bluetooth;final SoundDoorClient sound;final KeybootAPI api=new KeybootAPI();
    final Handler main=new Handler(Looper.getMainLooper());final ExecutorService worker=Executors.newSingleThreadExecutor();
    volatile JSONObject account;volatile List<Door> doors=new ArrayList<>();
    volatile boolean busy=false;volatile String message="登录后同步你有权使用的门禁";
    private volatile AtomicBoolean cancelled=new AtomicBoolean(false);
    private long serverTime,anchor;
    Runnable listener;
    PocketModel(Context c){context=c;settings=c.getSharedPreferences("preferences",Context.MODE_PRIVATE);secure=new SecureStore(c);bluetooth=new BluetoothDoorClient(c);sound=new SoundDoorClient(c);
        try{account=secure.read();}catch(Exception e){message="无法读取登录状态，请重新登录";}
        if(!settings.contains("deviceID"))settings.edit().putString("deviceID",UUID.randomUUID().toString().replace("-","")).apply();
    }
    void changed(){main.post(()->{if(listener!=null)listener.run();});}
    String accountTag(){if(account==null)return "";String key="shortcutAccountTag."+Door.str(account,"mobile");String tag=settings.getString(key,"");if(tag.isEmpty()){tag=UUID.randomUUID().toString();settings.edit().putString(key,tag).apply();}return tag;}
    String prefKey(String id){return "door."+(account==null?"signed-out":Door.str(account,"mobile"))+"."+id;}
    DoorPreference preference(Door d){try{return new DoorPreference(new JSONObject(settings.getString(prefKey(d.id),"{}")));}catch(Exception e){return new DoorPreference();}}
    void save(Door d,DoorPreference p){if(busy)return;try{settings.edit().putString(prefKey(d.id),p.json().toString()).apply();changed();}catch(Exception e){status("无法保存门设置");}}
    List<Door> favorites(){List<Door> result=new ArrayList<>();for(Door d:doors)if(preference(d).favorite)result.add(d);result.sort(Comparator.comparingInt(d->preference(d).order));return result;}
    Door find(String id){for(Door d:doors)if(d.id.equals(id))return d;return null;}
    void status(String value){message=value;changed();}
    interface Work { String run(AtomicBoolean cancelled)throws Exception; }
    void run(Work work){if(busy)return;busy=true;cancelled=new AtomicBoolean(false);AtomicBoolean flag=cancelled;changed();
        worker.execute(()->{try{String success=work.run(flag);if(flag.get())message="已取消，请确认门的实际状态";else message=success;}
            catch(Exception e){if(e instanceof KeybootAPI.ServiceError&&Arrays.asList("-400","-300").contains(((KeybootAPI.ServiceError)e).code)){try{secure.clear();}catch(Exception ignored){}account=null;doors=new ArrayList<>();}
                message=flag.get()?"已取消，请确认门的实际状态":e.getMessage()==null?"操作失败，请重试":e.getMessage();}
            finally{main.post(()->{busy=false;if(listener!=null)listener.run();});}});
    }
    void check(AtomicBoolean flag)throws Exception {if(flag.get()||Thread.currentThread().isInterrupted())throw new InterruptedException("已取消");}
    String model(){return Build.MANUFACTURER+" "+Build.MODEL;}
    void sendCode(String mobile){long available=settings.getLong("codeAvailableAt",0);if(System.currentTimeMillis()<available){status("请稍后再获取验证码");return;}run(flag->{api.sendCode(mobile,System.currentTimeMillis()/1000);settings.edit().putLong("codeAvailableAt",System.currentTimeMillis()+60000).apply();return "验证码已发送";});}
    void login(String mobile,String code){run(flag->{JSONObject a=api.login(mobile,code,settings.getString("deviceID",""),model());secure.write(a);account=a;doors=new ArrayList<>();check(flag);
        try{return sync(flag);}catch(Exception e){if(e instanceof KeybootAPI.ServiceError&&Arrays.asList("-400","-300").contains(((KeybootAPI.ServiceError)e).code))throw e;check(flag);return "登录成功，但钥匙同步失败："+e.getMessage()+"。请刷新重试。";}});}
    void absorb(JSONObject response)throws Exception {
        String token=Door.str(response,"token");if(!token.isEmpty()){JSONObject a=new JSONObject(account.toString());a.put("token",token);secure.write(a);account=a;}
        // Drop the previous snapshot before parsing so malformed data never preserves grants.
        doors=new ArrayList<>();long time=KeybootAPI.serverTime(response);List<Door> snapshot=Door.parse(response);serverTime=time;anchor=SystemClock.elapsedRealtime();doors=snapshot;
    }
    String sync(AtomicBoolean flag)throws Exception {if(account==null)throw new Exception("请先登录");JSONObject response=api.refresh(account,model());absorb(response);check(flag);
        boolean collections=false;for(String k:new String[]{"owner_keys","gate_keys","visitor_keys"})if(response.has(k)&&!response.isNull(k))collections=true;
        return !collections?"已登录，本次同步未返回钥匙数据，请刷新重试":doors.isEmpty()?"同步完成：账户当前没有可用钥匙":"已同步 "+doors.size()+" 把钥匙，请在配置页选择常用门";
    }
    void refresh(){run(this::sync);}
    long clock(){long elapsed=SystemClock.elapsedRealtime()-anchor;if(serverTime<=0||elapsed<0||elapsed>=120000)throw new IllegalStateException("服务器时间已过期，请刷新钥匙");return serverTime+elapsed/1000;}
    void open(String id,String shortcutTag){run(flag->{if(account==null)throw new Exception("请先登录");if(shortcutTag!=null&&!shortcutTag.equals(accountTag()))throw new Exception("请登录创建此快捷方式时的账户");
        status("正在检查最新授权…");sync(flag);check(flag);Door d=find(id);if(d==null)throw new Exception("这把钥匙已不在当前授权列表中");DoorPreference p=preference(d);
        if(shortcutTag!=null&&!p.favorite)throw new Exception("这把钥匙已取消常用，请重新选择");boolean audio="sound".equals(p.transport);d.validate(clock(),audio);
        if(!audio&&(d.type==6||d.type==7)){String token=api.verify(d,account);if(!token.isEmpty()){JSONObject a=new JSONObject(account.toString());a.put("token",token);secure.write(a);account=a;}}
        check(flag);if(audio)sound.open(d,p.band,this::clock,flag::get,this::status);else bluetooth.open(d,this::clock,flag::get,this::status);
        check(flag);return "开门请求已发送，请确认门的实际状态";
    });}
    void cancel(){if(busy){cancelled.set(true);bluetooth.cancel();sound.cancel();status("正在取消…");}}
    void logout(){if(busy)return;try{secure.clear();account=null;doors=new ArrayList<>();serverTime=0;status("已退出登录");}catch(Exception e){status("无法清除登录状态，请重试");}}
}
