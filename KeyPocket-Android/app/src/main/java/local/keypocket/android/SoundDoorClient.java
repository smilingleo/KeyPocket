package local.keypocket.android;

import android.content.Context;
import android.media.*;
import android.os.*;
import java.util.function.*;

final class SoundDoorClient {
    private final AudioManager manager;
    private volatile AudioTrack active;
    private volatile boolean stopped;
    SoundDoorClient(Context c){manager=c.getSystemService(AudioManager.class);}
    void cancel(){stopped=true;AudioTrack t=active;if(t!=null)try{t.pause();t.flush();}catch(Exception ignored){}}
    private void check(BooleanSupplier cancelled)throws Exception {if(stopped||cancelled.getAsBoolean()||Thread.currentThread().isInterrupted())throw new InterruptedException("声波已停止，请确认门的状态后重试");}
    private static boolean speaker(AudioDeviceInfo d){return d!=null&&d.getType()==AudioDeviceInfo.TYPE_BUILTIN_SPEAKER;}
    void open(Door door,int band,LongSupplier clock,BooleanSupplier cancelled,Consumer<String> status)throws Exception {
        stopped=false;check(cancelled);door.validate(clock.getAsLong(),true);
        if(manager==null)throw new Exception("此设备音频暂不可用");
        if(manager.getMode()!=AudioManager.MODE_NORMAL)throw new Exception("请先结束通话，再使用声波开门");
        if(manager.getStreamVolume(AudioManager.STREAM_MUSIC)<manager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)*.4)throw new Exception("请将媒体音量调到 40% 以上");
        AudioDeviceInfo selected=null;for(AudioDeviceInfo d:manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS))if(speaker(d)){selected=d;break;}
        if(selected==null)throw new Exception("找不到手机扬声器");
        AudioAttributes attributes=new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
        AudioFocusRequest focus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes).setAcceptsDelayedFocusGain(false).setOnAudioFocusChangeListener(change->{if(change!=AudioManager.AUDIOFOCUS_GAIN)cancel();},new Handler(Looper.getMainLooper())).build();
        AudioTrack track=null;boolean focused=false;
        try{
            if(manager.requestAudioFocus(focus)!=AudioManager.AUDIOFOCUS_REQUEST_GRANTED)throw new Exception("无法取得音频输出，请暂停其他音频后重试");focused=true;
            int buffer=Math.max(AudioTrack.getMinBufferSize(44100,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT),8820);
            track=new AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(new AudioFormat.Builder().setSampleRate(44100).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()).setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(buffer).build();
            active=track;if(track.getState()!=AudioTrack.STATE_INITIALIZED||!track.setPreferredDevice(selected))throw new Exception("无法切换到手机扬声器，请断开耳机后重试");
            track.addOnRoutingChangedListener(router->{AudioDeviceInfo d=router.getRoutedDevice();if(d!=null&&!speaker(d))cancel();},new Handler(Looper.getMainLooper()));
            status.accept("正在检查手机扬声器输出…");track.play();byte[] silence=new byte[4410];long ready=0,start=SystemClock.elapsedRealtime();
            while(SystemClock.elapsedRealtime()-start<2000){check(cancelled);if(track.write(silence,0,silence.length,AudioTrack.WRITE_BLOCKING)<0)throw new Exception("音频输出失败");
                long now=SystemClock.elapsedRealtime();if(speaker(track.getRoutedDevice())){if(ready==0)ready=now;if(now-ready>=200)break;}else ready=0;
            }
            check(cancelled);if(ready==0||!speaker(track.getRoutedDevice())||SystemClock.elapsedRealtime()-ready<200)throw new Exception("未确认扬声器输出，请断开蓝牙或有线耳机后重试");
            // Generate the time-sensitive authorization only after a verified speaker route.
            byte[] pcm=SoundProtocol.pcm(SoundProtocol.authorization(door,clock.getAsLong()),band);check(cancelled);status.accept("正在通过手机扬声器发送…");
            for(int offset=0;offset<pcm.length;){check(cancelled);if(!speaker(track.getRoutedDevice()))throw new Exception("声音输出已改变，已停止开门请求");int written=track.write(pcm,offset,Math.min(2048,pcm.length-offset),AudioTrack.WRITE_BLOCKING);if(written<=0)throw new Exception("音频传输中断");offset+=written;}
            long end=SystemClock.elapsedRealtime()+500;while(SystemClock.elapsedRealtime()<end){check(cancelled);if(!speaker(track.getRoutedDevice()))throw new Exception("声音输出已改变，未确认请求完成");Thread.sleep(20);}
        }finally{active=null;if(track!=null){try{track.stop();}catch(Exception ignored){}track.release();}if(focused)manager.abandonAudioFocusRequest(focus);}
    }
}
