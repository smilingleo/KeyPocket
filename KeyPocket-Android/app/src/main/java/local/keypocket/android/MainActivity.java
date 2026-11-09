package local.keypocket.android;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import java.text.SimpleDateFormat;
import java.util.*;

public final class MainActivity extends Activity {
    private static final int INK=0xff153c33,TEAL=0xff17745f,MUTED=0xff65746e,BG=0xfff4f7f5;
    private PocketModel model;
    private LinearLayout page,content;
    private EditText mobile,code;
    private TextView status;
    private boolean config=false,didInitialSync=false,destroyed=false;
    private String shortcutDoor,shortcutTag,permissionDoor,permissionTag;
    private String savedMobile="",savedCode="";
    @Override public void onCreate(Bundle saved){super.onCreate(saved);model=PocketModel.get(this);if(saved!=null){config=saved.getBoolean("config");savedMobile=saved.getString("mobile","");savedCode=saved.getString("code","");}
        readIntent(getIntent());getWindow().setStatusBarColor(BG);getWindow().setNavigationBarColor(BG);render();}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);readIntent(intent);config=false;render();if(model.account!=null&&!model.busy)model.refresh();}
    private void readIntent(Intent intent){if("local.keypocket.SHOW_DOOR".equals(intent.getAction())){shortcutDoor=intent.getStringExtra("door");shortcutTag=intent.getStringExtra("accountTag");}}
    @Override protected void onResume(){super.onResume();destroyed=false;model.listener=this::onModelChanged;
        if(!didInitialSync&&model.account!=null){didInitialSync=true;if(!model.busy)model.refresh();}onModelChanged();}
    @Override protected void onStop(){model.listener=null;model.cancel();super.onStop();}
    @Override protected void onDestroy(){destroyed=true;super.onDestroy();}
    @Override protected void onSaveInstanceState(Bundle out){out.putBoolean("config",config);out.putString("mobile",mobile==null?savedMobile:mobile.getText().toString());out.putString("code",code==null?savedCode:code.getText().toString());super.onSaveInstanceState(out);}
    private void onModelChanged(){if(destroyed||isFinishing())return;render();if(!model.busy){ShortcutPublisher.publish(this,model);maybeShortcut();}}
    private int dp(float x){return (int)(getResources().getDisplayMetrics().density*x+.5f);}
    private GradientDrawable background(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    private TextView text(String s,int size,int color,boolean bold){TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);t.setLineSpacing(dp(3),1);return t;}
    private LinearLayout column(){LinearLayout v=new LinearLayout(this);v.setOrientation(LinearLayout.VERTICAL);return v;}
    private LinearLayout row(){LinearLayout v=new LinearLayout(this);v.setGravity(Gravity.CENTER_VERTICAL);v.setOrientation(LinearLayout.HORIZONTAL);return v;}
    private void space(LinearLayout v,int size){View x=new View(this);v.addView(x,new LinearLayout.LayoutParams(1,dp(size)));}
    private Button button(String name,Runnable action,boolean primary){Button b=new Button(this);b.setText(name);b.setAllCaps(false);b.setTextSize(15);b.setMinHeight(dp(48));b.setPadding(dp(12),dp(6),dp(12),dp(6));b.setTextColor(primary?Color.WHITE:TEAL);b.setBackground(background(primary?TEAL:0xffe7efea,13));b.setEnabled(!model.busy);b.setAlpha(model.busy?.5f:1);b.setOnClickListener(v->action.run());return b;}
    private void label(String name){space(content,20);content.addView(text(name,18,INK,true));space(content,10);}
    private EditText input(String hint,int type){EditText e=new EditText(this);e.setTextSize(17);e.setSingleLine();e.setHint(hint);e.setInputType(type);e.setPadding(dp(14),dp(12),dp(14),dp(12));e.setBackground(background(0xffedf3ef,12));e.setEnabled(!model.busy);return e;}
    private void render(){
        if(mobile!=null){savedMobile=mobile.getText().toString();savedCode=code.getText().toString();}mobile=null;code=null;
        page=column();page.setBackgroundColor(BG);
        page.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){android.graphics.Insets i=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.displayCutout()|WindowInsets.Type.ime());v.setPadding(i.left,i.top,i.right,i.bottom);}else v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);content=column();content.setPadding(dp(22),dp(18),dp(22),dp(24));scroll.addView(content);page.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout header=row();ImageView icon=new ImageView(this);icon.setImageResource(R.mipmap.ic_launcher);icon.setClipToOutline(true);icon.setBackground(background(TEAL,15));header.addView(icon,new LinearLayout.LayoutParams(dp(54),dp(54)));
        LinearLayout heading=column();heading.setPadding(dp(14),0,0,0);heading.addView(text("钥匙口袋",26,INK,true));heading.addView(text("你的门，随手可达",13,MUTED,false));header.addView(heading,new LinearLayout.LayoutParams(0,-2,1));content.addView(header);space(content,20);
        status=text(model.message,14,MUTED,false);status.setPadding(dp(15),dp(13),dp(15),dp(13));status.setBackground(background(0xffe7efea,14));status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);content.addView(status);
        if(model.busy){space(content,10);ProgressBar progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setIndeterminate(true);content.addView(progress,new LinearLayout.LayoutParams(-1,dp(4)));Button cancel=button("取消当前操作",model::cancel,false);cancel.setEnabled(true);cancel.setAlpha(1);space(content,10);content.addView(cancel);}
        if(model.account==null)login();else if(config)configuration();else favorites();
        if(model.account!=null){LinearLayout nav=row();nav.setPadding(dp(20),dp(10),dp(20),dp(10));nav.setBackgroundColor(Color.WHITE);Button a=button("常用门",()->{config=false;render();},!config);Button b=button("钥匙配置",()->{config=true;render();},config);nav.addView(a,new LinearLayout.LayoutParams(0,dp(50),1));View gap=new View(this);nav.addView(gap,new LinearLayout.LayoutParams(dp(12),1));nav.addView(b,new LinearLayout.LayoutParams(0,dp(50),1));page.addView(nav);}
        setContentView(page);page.requestApplyInsets();
    }
    private void login(){label("账户登录");content.addView(text("使用已有钥匙宝手机号登录，同步账户授权的钥匙。",15,MUTED,false));space(content,16);
        mobile=input("手机号",android.text.InputType.TYPE_CLASS_PHONE);mobile.setText(savedMobile);mobile.setAutofillHints(View.AUTOFILL_HINT_PHONE);content.addView(mobile);space(content,12);
        code=input("短信验证码",android.text.InputType.TYPE_CLASS_NUMBER);code.setText(savedCode);content.addView(code);space(content,14);
        content.addView(button("获取验证码",()->{String m=mobile.getText().toString().trim();hideKeyboard();model.sendCode(m);},false));space(content,12);
        content.addView(button("登录并同步钥匙",()->{String m=mobile.getText().toString().trim(),c=code.getText().toString().trim();hideKeyboard();didInitialSync=true;model.login(m,c);},true));space(content,22);
        content.addView(text("仅使用你已有权限的门禁。登录状态使用 Android Keystore 加密保存在本机。",13,MUTED,false));
    }
    private void hideKeyboard(){InputMethodManager i=getSystemService(InputMethodManager.class);if(i!=null)i.hideSoftInputFromWindow(page.getWindowToken(),0);}
    private void favorites(){label("常用门");content.addView(button("刷新钥匙",model::refresh,false));space(content,14);
        List<Door> favorites=model.favorites();if(favorites.isEmpty()){LinearLayout empty=column();empty.setPadding(dp(20),dp(24),dp(20),dp(24));empty.setBackground(background(Color.WHITE,18));empty.addView(text("把常用钥匙放在这里",21,INK,true));space(empty,10);empty.addView(text(model.doors.isEmpty()?"刷新钥匙后，在配置页选择常用门。":"打开配置页，为你常用的门开启「设为常用」。",15,MUTED,false));content.addView(empty);}
        for(Door d:favorites){DoorPreference p=model.preference(d);LinearLayout card=column();card.setPadding(dp(18),dp(18),dp(18),dp(18));card.setBackground(background(Color.WHITE,18));card.addView(text(p.title(d),21,INK,true));space(card,7);card.addView(text(("sound".equals(p.transport)?"声波 · 手机扬声器":"蓝牙 · 靠近门禁")+"  ·  "+(d.enabled?"已授权":"已停用"),13,MUTED,false));space(card,16);
            Button open=button("打开这扇门",()->requestOpen(d.id,null),true);if(!d.bluetooth()&&!d.sound()){open.setEnabled(false);open.setText("此钥匙类型暂不支持");}card.addView(open);space(card,8);card.addView(button("钥匙设置",()->settings(d),false));content.addView(card);space(content,14);}
        space(content,12);content.addView(text("「已发送」表示请求已传输，请确认门的实际状态。",12,MUTED,false));
    }
    private void configuration(){label("系统快捷入口");content.addView(text("长按桌面 App 图标可选择常用门；钥匙设置中可以添加单把钥匙到桌面。下拉快捷设置面板，编辑并添加「常用门」磁贴。",14,MUTED,false));
        label("常用门顺序");List<Door> favorites=model.favorites();if(favorites.isEmpty())content.addView(text("还没有常用门",14,MUTED,false));for(int n=0;n<favorites.size();n++){final int index=n;Door d=favorites.get(n);LinearLayout r=row();r.addView(text(model.preference(d).title(d),15,INK,true),new LinearLayout.LayoutParams(0,-2,1));Button up=button("↑",()->move(favorites,index,-1),false),down=button("↓",()->move(favorites,index,1),false);up.setContentDescription("上移 "+model.preference(d).title(d));down.setContentDescription("下移 "+model.preference(d).title(d));up.setEnabled(!model.busy&&n>0);down.setEnabled(!model.busy&&n<favorites.size()-1);r.addView(up,new LinearLayout.LayoutParams(dp(48),dp(48)));r.addView(down,new LinearLayout.LayoutParams(dp(48),dp(48)));content.addView(r);space(content,6);}
        label("账户授权的门 · "+model.doors.size());content.addView(button("刷新钥匙",model::refresh,false));space(content,10);for(Door d:model.doors){DoorPreference p=model.preference(d);Button b=button((p.favorite?"★  ":"")+p.title(d)+"  ›",()->settings(d),false);b.setGravity(Gravity.START|Gravity.CENTER_VERTICAL);content.addView(b);space(content,8);}
        label("账户");String m=Door.str(model.account,"mobile");content.addView(text(m.length()==11?m.substring(0,3)+"****"+m.substring(7):"已登录",15,MUTED,false));space(content,10);content.addView(button("退出登录",()->new AlertDialog.Builder(this).setTitle("退出登录？").setMessage("本机快捷入口将停用。门的别名和常用设置会保留。").setNegativeButton("取消",null).setPositiveButton("退出",(x,w)->{model.logout();shortcutDoor=null;}).show(),false));space(content,14);content.addView(text("钥匙口袋 Android 1.0",12,MUTED,false));
    }
    private void move(List<Door> list,int from,int delta){Collections.swap(list,from,from+delta);for(int i=0;i<list.size();i++){DoorPreference p=model.preference(list.get(i));p.order=i;model.save(list.get(i),p);}}
    private void settings(Door d){if(model.busy)return;DoorPreference p=model.preference(d);LinearLayout form=column();form.setPadding(dp(24),dp(12),dp(24),dp(4));EditText alias=input("本机别名（可选）",android.text.InputType.TYPE_CLASS_TEXT);alias.setText(p.alias);alias.setSingleLine(false);form.addView(alias);space(form,12);CheckBox favorite=new CheckBox(this);favorite.setText("设为常用");favorite.setChecked(p.favorite);form.addView(favorite);space(form,12);
        form.addView(text("开门方式",14,INK,true));RadioGroup transports=new RadioGroup(this);RadioButton ble=new RadioButton(this);ble.setId(View.generateViewId());ble.setText("蓝牙");ble.setEnabled(d.bluetooth());transports.addView(ble);RadioButton sound=new RadioButton(this);sound.setId(View.generateViewId());sound.setText("声波 · 手机扬声器");sound.setEnabled(d.sound());transports.addView(sound);transports.check("sound".equals(p.transport)?sound.getId():ble.getId());form.addView(transports);
        Spinner bands=new Spinner(this);bands.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,new String[]{"标准频段","低频兼容","高频"}));bands.setSelection(p.band==9000?1:p.band==17000?2:0);form.addView(bands);space(form,14);
        form.addView(text("授权到期："+new SimpleDateFormat("yyyy-MM-dd HH:mm",Locale.CHINA).format(new Date(d.expires*1000))+"\n钥匙类型："+d.type+" · "+(d.enabled?"已启用":"已停用"),12,MUTED,false));space(form,10);
        form.addView(text("声波会暂时暂停其他音频。若系统不能将声音切换到扬声器，会提示断开耳机后重试。",12,MUTED,false));ScrollView scroll=new ScrollView(this);scroll.addView(form);
        Runnable save=()->{p.alias=alias.getText().toString().trim();if(p.alias.length()>60)p.alias=p.alias.substring(0,60);p.favorite=favorite.isChecked();p.transport=transports.getCheckedRadioButtonId()==sound.getId()?"sound":"bluetooth";p.band=bands.getSelectedItemPosition()==1?9000:bands.getSelectedItemPosition()==2?17000:12200;model.save(d,p);};
        new AlertDialog.Builder(this).setTitle("钥匙设置").setView(scroll).setNegativeButton("取消",null).setPositiveButton("保存",(v,w)->save.run()).setNeutralButton("添加到桌面",(v,w)->{favorite.setChecked(true);save.run();if(!ShortcutPublisher.pin(this,d,model))model.status("当前桌面不支持固定快捷方式，可尝试长按 App 图标");else model.status("请在系统提示中确认添加桌面钥匙");}).show();
    }
    private void maybeShortcut(){if(shortcutDoor==null||model.account==null||model.busy)return;String id=shortcutDoor,tag=shortcutTag;shortcutDoor=null;shortcutTag=null;
        Door d=model.find(id);if(tag==null||!tag.equals(model.accountTag())||d==null||!model.preference(d).favorite){model.status("此快捷方式已失效，请刷新并重新选择常用门");return;}
        // External launcher intents only select a key. An explicit user confirmation is required before transmitting.
        new AlertDialog.Builder(this).setTitle("打开 "+model.preference(d).title(d)+"？").setMessage("将检查最新授权，并使用这把钥匙配置的开门方式。").setNegativeButton("取消",null).setPositiveButton("开门",(v,w)->requestOpen(id,tag)).show();
    }
    private void requestOpen(String id,String tag){if(model.busy)return;KeyguardManager keyguard=getSystemService(KeyguardManager.class);if(keyguard!=null&&keyguard.isKeyguardLocked()){keyguard.requestDismissKeyguard(this,new KeyguardManager.KeyguardDismissCallback(){@Override public void onDismissSucceeded(){requestOpen(id,tag);}});return;}
        Door d=model.find(id);if(d==null){model.status("请刷新后重新选择钥匙");return;}boolean sound="sound".equals(model.preference(d).transport);
        if(!sound){String[] permissions=Build.VERSION.SDK_INT>=31?new String[]{Manifest.permission.BLUETOOTH_SCAN,Manifest.permission.BLUETOOTH_CONNECT}:new String[]{Manifest.permission.ACCESS_FINE_LOCATION};List<String> missing=new ArrayList<>();for(String permission:permissions)if(checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)missing.add(permission);
            if(!missing.isEmpty()){permissionDoor=id;permissionTag=tag;requestPermissions(missing.toArray(new String[0]),100);return;}
            if(Build.VERSION.SDK_INT<31){android.location.LocationManager location=getSystemService(android.location.LocationManager.class);if(location!=null&&!location.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)&&!location.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER)){new AlertDialog.Builder(this).setTitle("请开启系统定位服务").setMessage("Android 8–11 的蓝牙扫描需要系统定位开关；本 App 不读取 GPS 位置。").setNegativeButton("取消",null).setPositiveButton("去设置",(v,w)->startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))).show();return;}}
        }
        model.open(id,tag);
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){super.onRequestPermissionsResult(request,permissions,results);if(request==100){String id=permissionDoor,tag=permissionTag;permissionDoor=null;permissionTag=null;boolean ok=results.length>0;for(int result:results)ok&=result==PackageManager.PERMISSION_GRANTED;if(ok&&id!=null)requestOpen(id,tag);else new AlertDialog.Builder(this).setTitle("需要蓝牙权限").setMessage("请在应用设置中允许附近设备权限（Android 8–11 为定位权限），然后再次点击开门。").setNegativeButton("取消",null).setPositiveButton("应用设置",(v,w)->startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,android.net.Uri.parse("package:"+getPackageName())))).show();}}
}
