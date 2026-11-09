package local.keypocket.android;

import java.util.*;
import org.json.*;

final class Door {
    String id, title, project, license, floor, group;
    long keyID, expires;
    int type;
    boolean enabled;
    boolean bluetooth() { return type==0||type==3||type==5||type==6||type==7||type==100; }
    boolean sound() { return type==0||type==3||type==100; }
    void validate(long now, boolean sound) throws Exception {
        if (!enabled || expires<=now) throw new Exception("钥匙已过期或停用，请刷新钥匙");
        if (sound ? !sound() : !bluetooth()) throw new Exception("此钥匙类型暂不支持所选开门方式");
        if (keyID<0 && (sound||type!=5)) throw new Exception("钥匙编号无效");
        Protocol.hex3(sound&&type==100?project:license);
        if (!sound) Protocol.hex3(project);
        if (sound && type!=100) {
            int f=Integer.parseInt(floor.isEmpty()?"0":floor);
            if(f<0||f>127)throw new Exception("此楼层编码暂不支持声波");
        } else if (!sound && type==5) { Long.parseUnsignedLong(floor,16); }
        else if (!sound && type!=3 && type!=100) {
            int f=Integer.parseInt(floor);if(f<1||f>31)throw new Exception("此楼层编码需要额外适配");
        }
    }
    static String str(JSONObject o,String key) { Object v=o.opt(key);return v==null||v==JSONObject.NULL?"":String.valueOf(v); }
    static List<Door> parse(JSONObject response) throws Exception {
        List<Door> out=new ArrayList<>();Set<String> seen=new HashSet<>();
        for(String group:new String[]{"owner_keys","gate_keys","visitor_keys"}) {
            Object raw=response.opt(group);if(raw==null||raw==JSONObject.NULL)continue;
            if(raw instanceof String)raw=new JSONArray((String)raw);
            if(!(raw instanceof JSONArray))throw new Exception("钥匙列表格式不兼容："+group);
            JSONArray rows=(JSONArray)raw;
            for(int n=0;n<rows.length();n++) {
                JSONObject row=rows.getJSONObject(n);
                int type=Integer.parseInt(str(row,"type")); long expiry=Long.parseLong(str(row,"end_time"));
                StringJoiner title=new StringJoiner(" · ");
                for(String k:new String[]{"project_name","build_num","unit_num","lift_num","floor_num"})if(!str(row,k).isEmpty())title.add(str(row,k));
                JSONArray ids=row.optJSONArray("ids"),licenses=row.optJSONArray("licenses"),floors=row.optJSONArray("floor_stations");
                int count=type==5&&licenses!=null?licenses.length():1;
                if(type==5&&(licenses==null||count==0||ids==null||floors==null||ids.length()!=count||floors.length()!=count))throw new Exception("组合钥匙数据不完整");
                for(int i=0;i<count;i++) {
                    Door d=new Door();String rawID=type==5?ids.getString(i):str(row,"id");
                    d.id=group+":"+rawID+":"+i;d.keyID=Long.parseLong(rawID);d.type=type;d.expires=expiry;d.group=group;
                    d.title=title.length()==0?"门 "+rawID:title.toString()+(count>1?" · "+(i+1):"");
                    d.project=str(row,"project_license").toLowerCase(Locale.ROOT);
                    d.license=(type==5?licenses.getString(i):type==100?"000000":str(row,"license")).toLowerCase(Locale.ROOT);
                    d.floor=type==5?floors.getString(i):type==100?"0":str(row,"floor_station");
                    d.enabled=!"0".equals(str(row,"enable"));
                    if(!seen.add(d.id))throw new Exception("服务器返回重复钥匙，请重新刷新");out.add(d);
                }
            }
        }
        return out;
    }
}
