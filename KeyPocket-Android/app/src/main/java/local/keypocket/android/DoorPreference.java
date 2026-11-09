package local.keypocket.android;

import org.json.*;

final class DoorPreference {
    String alias="",transport="bluetooth";
    boolean favorite=false;
    int order=0,band=12200;
    DoorPreference(){}
    DoorPreference(JSONObject o){alias=o.optString("alias","");favorite=o.optBoolean("favorite",false);order=o.optInt("order",0);transport="sound".equals(o.optString("transport"))?"sound":"bluetooth";int v=o.optInt("band",12200);band=v==9000||v==17000?v:12200;}
    JSONObject json()throws Exception{return new JSONObject().put("alias",alias).put("favorite",favorite).put("order",order).put("transport",transport).put("band",band);}
    String title(Door d){return alias.trim().isEmpty()?d.title:alias.trim();}
}
