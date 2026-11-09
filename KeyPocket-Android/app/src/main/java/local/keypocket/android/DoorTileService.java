package local.keypocket.android;

import android.service.quicksettings.*;
import android.app.PendingIntent;
import android.os.Build;

public final class DoorTileService extends TileService {
    @Override public void onStartListening(){super.onStartListening();Tile tile=getQsTile();if(tile!=null){tile.setState(Tile.STATE_INACTIVE);tile.setLabel("常用门");tile.updateTile();}}
    @Override public void onClick(){super.onClick();Runnable action=()->{
        android.content.Intent i=ShortcutPublisher.intent(this,null,"");
        if(Build.VERSION.SDK_INT>=34)startActivityAndCollapse(PendingIntent.getActivity(this,0,i,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE));
        else startActivityAndCollapse(i);
    };if(isLocked())unlockAndRun(action);else action.run();}
}
