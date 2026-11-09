package local.keypocket.android;

import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.graphics.drawable.Icon;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class ShortcutPublisher {
    static Intent intent(Context c,Door d,String tag){Intent i=new Intent(c,MainActivity.class).setAction("local.keypocket.SHOW_DOOR").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);if(d!=null)i.putExtra("door",d.id).putExtra("accountTag",tag);return i;}
    static String id(Door d,String tag){return UUID.nameUUIDFromBytes((tag+"|"+d.id).getBytes(StandardCharsets.UTF_8)).toString();}
    static ShortcutInfo info(Context c,Door d,PocketModel model){String title=model.preference(d).title(d);if(title.length()>35)title=title.substring(0,35);return new ShortcutInfo.Builder(c,id(d,model.accountTag())).setShortLabel(title).setLongLabel("打开 "+title).setIcon(Icon.createWithResource(c,R.drawable.ic_key)).setIntent(intent(c,d,model.accountTag())).build();}
    static void publish(Context c,PocketModel m){
        ShortcutManager manager=c.getSystemService(ShortcutManager.class);if(manager==null)return;
        try{List<Door> favorites=m.favorites();List<ShortcutInfo> dynamic=new ArrayList<>();Set<String> valid=new HashSet<>();int max=Math.min(4,manager.getMaxShortcutCountPerActivity());
            for(Door d:favorites){valid.add(id(d,m.accountTag()));if(dynamic.size()<max)dynamic.add(info(c,d,m));}
            List<String> invalid=new ArrayList<>(),enabled=new ArrayList<>();for(ShortcutInfo pinned:manager.getPinnedShortcuts()){if(!valid.contains(pinned.getId()))invalid.add(pinned.getId());else enabled.add(pinned.getId());}
            // During a cold-start sync the in-memory list is empty; do not invalidate pinned keys until an explicit snapshot or logout.
            if(m.account==null||!m.doors.isEmpty()||!m.busy){if(!invalid.isEmpty())manager.disableShortcuts(invalid,"请打开钥匙口袋刷新并重新选择常用门");}
            if(!enabled.isEmpty())manager.enableShortcuts(enabled);if(!manager.isRateLimitingActive())manager.setDynamicShortcuts(dynamic);
        }catch(Exception ignored){}
    }
    static boolean pin(Context c,Door d,PocketModel m){ShortcutManager manager=c.getSystemService(ShortcutManager.class);return manager!=null&&manager.isRequestPinShortcutSupported()&&manager.requestPinShortcut(info(c,d,m),null);}
}
