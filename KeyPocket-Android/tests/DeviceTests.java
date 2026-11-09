package local.keypocket.tests;

import android.app.Instrumentation;
import android.content.*;
import android.content.pm.*;
import android.os.*;
import java.lang.reflect.*;
import java.util.*;
import org.json.*;

public final class DeviceTests extends Instrumentation {
    int assertions=0;
    void screenshot(String name)throws Exception {
        waitForIdleSync();SystemClock.sleep(300);
        android.graphics.Bitmap bitmap=getUiAutomation().takeScreenshot();
        if(bitmap==null)throw new AssertionError("Missing screenshot");
        java.io.File dir=new java.io.File(getTargetContext().getExternalFilesDir(null),"qa");dir.mkdirs();
        try(java.io.FileOutputStream out=new java.io.FileOutputStream(new java.io.File(dir,name+".png"))){bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);}bitmap.recycle();
    }
    void check(boolean ok,String what){if(!ok)throw new AssertionError(what);assertions++;}
    Object call(Class<?> cls,Object target,String name,Class<?>[] types,Object...args)throws Exception {Method m=cls.getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(target,args);}
    void set(Class<?> cls,Object target,String name,Object value)throws Exception {Field f=cls.getDeclaredField(name);f.setAccessible(true);f.set(target,value);}
    Object get(Class<?> cls,Object target,String name)throws Exception {Field f=cls.getDeclaredField(name);f.setAccessible(true);return f.get(target);}
    @Override public void onCreate(Bundle args){super.onCreate(args);start();}
    @Override public void onStart(){Bundle result=new Bundle();try{
        Context c=getTargetContext();ClassLoader loader=c.getClassLoader();
        Class<?> secureClass=Class.forName("local.keypocket.android.SecureStore",true,loader);Constructor<?> ctor=secureClass.getDeclaredConstructor(Context.class);ctor.setAccessible(true);Object secure=ctor.newInstance(c);
        check(call(secureClass,secure,"read",new Class<?>[]{})==null,"Test requires an empty emulator account");
        JSONObject synthetic=new JSONObject().put("mobile","13800000000").put("token","synthetic-device-test-token").put("device_id","test-device");
        call(secureClass,secure,"write",new Class<?>[]{JSONObject.class},synthetic);JSONObject loaded=(JSONObject)call(secureClass,secure,"read",new Class<?>[]{});check(loaded.getString("token").equals("synthetic-device-test-token"),"Keystore round-trip");
        String encrypted=c.getSharedPreferences("secure-session",Context.MODE_PRIVATE).getString("account","");check(!encrypted.contains("synthetic")&&!encrypted.contains("token"),"Encrypted session at rest");
        call(secureClass,secure,"clear",new Class<?>[]{});check(call(secureClass,secure,"read",new Class<?>[]{})==null,"Logout clears secure account");
        Class<?> modelClass=Class.forName("local.keypocket.android.PocketModel",true,loader),doorClass=Class.forName("local.keypocket.android.Door",true,loader),publisher=Class.forName("local.keypocket.android.ShortcutPublisher",true,loader);
        Object model=call(modelClass,null,"get",new Class<?>[]{Context.class},c);
        JSONObject row=new JSONObject().put("id","123").put("type",0).put("end_time","1800000000").put("project_license","010203").put("license","a1b2c3").put("floor_station","7").put("project_name","测试南门");
        List<?> doors=(List<?>)call(doorClass,null,"parse",new Class<?>[]{JSONObject.class},new JSONObject().put("owner_keys",new JSONArray().put(row)));
        final Throwable[] mainError={null};runOnMainSync(()->{try{
            set(modelClass,model,"account",synthetic);set(modelClass,model,"doors",doors);
            Object pref=call(modelClass,model,"preference",new Class<?>[]{doorClass},doors.get(0));set(pref.getClass(),pref,"favorite",true);call(modelClass,model,"save",new Class<?>[]{doorClass,pref.getClass()},doors.get(0),pref);
            call(publisher,null,"publish",new Class<?>[]{Context.class,modelClass},c,model);
        }catch(Throwable t){mainError[0]=t;}});if(mainError[0]!=null)throw new Exception(mainError[0]);
        ShortcutManager sm=c.getSystemService(ShortcutManager.class);check(sm.getDynamicShortcuts().size()==1,"Dynamic favorite shortcut published");ShortcutInfo info=sm.getDynamicShortcuts().get(0);check(info.getShortLabel().toString().equals("测试南门"),"Shortcut label");check(info.getIntent().getStringExtra("door").equals("owner_keys:123:0"),"Shortcut selects authorized key");
        String firstTag=(String)call(modelClass,model,"accountTag",new Class<?>[]{});
        runOnMainSync(()->{try{call(modelClass,model,"open",new Class<?>[]{String.class,String.class},"owner_keys:123:0","wrong-account");}catch(Throwable t){mainError[0]=t;}});
        long limit=SystemClock.elapsedRealtime()+3000;while((Boolean)get(modelClass,model,"busy")&&SystemClock.elapsedRealtime()<limit)SystemClock.sleep(20);
        check(!(Boolean)get(modelClass,model,"busy"),"Rejected shortcut task completes");check(get(modelClass,model,"message").equals("请登录创建此快捷方式时的账户"),"Wrong-account shortcut rejected before any network or BLE");
        runOnMainSync(()->{try{call(modelClass,model,"logout",new Class<?>[]{});call(publisher,null,"publish",new Class<?>[]{Context.class,modelClass},c,model);}catch(Throwable t){mainError[0]=t;}});if(mainError[0]!=null)throw new Exception(mainError[0]);
        check(sm.getDynamicShortcuts().isEmpty(),"Logout removes dynamic shortcuts");
        PackageInfo pi=c.getPackageManager().getPackageInfo(c.getPackageName(),PackageManager.GET_PERMISSIONS);List<String> permissions=Arrays.asList(pi.requestedPermissions);check(!permissions.contains("android.permission.RECORD_AUDIO"),"No microphone permission");check(!permissions.contains("android.permission.READ_CONTACTS"),"No contacts permission");check(pi.applicationInfo.targetSdkVersion==36,"Targets API 36");
        // Render test fixtures only after the login Activity has resumed: no auto-sync or live auth calls.
        android.app.Activity activity=startActivitySync(c.getPackageManager().getLaunchIntentForPackage(c.getPackageName()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        waitForIdleSync();screenshot("login");
        runOnMainSync(()->{try{
            set(modelClass,model,"account",synthetic);set(modelClass,model,"doors",doors);set(modelClass,model,"message","已同步 1 把钥匙 · 测试数据");
            Object p=call(modelClass,model,"preference",new Class<?>[]{doorClass},doors.get(0));set(p.getClass(),p,"favorite",true);set(p.getClass(),p,"alias","小区南门");call(modelClass,model,"save",new Class<?>[]{doorClass,p.getClass()},doors.get(0),p);
            call(activity.getClass(),activity,"render",new Class<?>[]{});
        }catch(Throwable t){mainError[0]=t;}});waitForIdleSync();if(mainError[0]!=null)throw new Exception(mainError[0]);screenshot("favorites");
        runOnMainSync(()->{try{set(activity.getClass(),activity,"config",true);call(activity.getClass(),activity,"render",new Class<?>[]{});}catch(Throwable t){mainError[0]=t;}});waitForIdleSync();screenshot("configuration");
        runOnMainSync(()->{try{call(activity.getClass(),activity,"settings",new Class<?>[]{doorClass},doors.get(0));}catch(Throwable t){mainError[0]=t;}});waitForIdleSync();screenshot("door-settings");
        runOnMainSync(()->{try{set(modelClass,model,"account",null);set(modelClass,model,"doors",new ArrayList<>());activity.finish();}catch(Throwable t){mainError[0]=t;}});waitForIdleSync();if(mainError[0]!=null)throw new Exception(mainError[0]);
        c.getSharedPreferences("preferences",Context.MODE_PRIVATE).edit().clear().commit();
        result.putString("stream","PASS: "+assertions+" Android runtime assertions: Keystore, shortcut publication, account isolation, logout, manifest. No real network or door requests.\n");finish(-1,result);
    }catch(Throwable error){result.putString("stream","FAIL: "+error+"\n"+android.util.Log.getStackTraceString(error));finish(0,result);}}
}
