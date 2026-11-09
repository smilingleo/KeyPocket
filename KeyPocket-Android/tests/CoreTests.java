package local.keypocket.android;

import java.util.*;
import java.nio.charset.StandardCharsets;
import java.net.URLDecoder;
import java.security.MessageDigest;
import org.json.*;

public final class CoreTests {
    static int passed=0;
    static void equal(Object a,Object b){if(!Objects.equals(a,b))throw new AssertionError("Expected "+b+", got "+a);passed++;}
    interface Throwing {void run()throws Exception;}
    static void rejects(Throwing f)throws Exception{try{f.run();}catch(Exception expected){passed++;return;}throw new AssertionError("Expected rejection");}
    static String hex(byte[] b){StringBuilder out=new StringBuilder();for(byte x:b)out.append(String.format(Locale.ROOT,"%02x",x&255));return out.toString();}
    static Door door(int type){Door d=new Door();d.id="synthetic";d.keyID=type==5?-1:123456;d.title="Synthetic";d.project="010203";d.license=type==100?"000000":"a1b2c3";d.floor=type==100?"0":type==5?"0000000000000041":"7";d.type=type;d.expires=1800000000;d.enabled=true;return d;}
    static JSONObject row()throws Exception{return new JSONObject().put("id","12").put("type",0).put("end_time","1800000000").put("project_license","010203").put("license","a1b2c3").put("floor_station","7").put("project_name","小区");}
    static String envelope(JSONObject o)throws Exception{return Protocol.encrypt(o.toString().getBytes(StandardCharsets.UTF_8));}
    static JSONObject fields(String body)throws Exception{return new JSONObject(new String(Protocol.decrypt(URLDecoder.decode(body.substring("jiami_data=".length()),"UTF-8")),StandardCharsets.UTF_8));}
    public static void main(String[] args)throws Exception {
        byte[] token={7,6,5,4,3,2,1,0},challenge=new byte[18];for(int i=0;i<8;i++)challenge[8+i]=(byte)i;
        equal(hex(Protocol.challenge(challenge)[0]),hex(token));equal(hex(Protocol.challenge(challenge)[1]),"55aa12c500000000f3ad2a90e32161a733fb");rejects(()->Protocol.challenge(new byte[17]));
        int[] families={0,3,5,6,7,100};String[] vectors={"863fc6355229333375f3eee25fe85e2d47b73096e19bc4c5fad26283173673c6c215291dafbeaf9d","3ffe8c98ecc177ec75f3eee25fe85e2d876666100aeb487b04e0b01400a94c3cc215291dafbeaf9d","3ffe8c98ecc177eccb1225c97c889c3a47b73096e19bc4c5e8ba126febb05d67c215291dafbeaf9d","863fc6355229333375f3eee25fe85e2d47b73096e19bc4c5fad26283173673c6c215291dafbeaf9d","863fc6355229333375f3eee25fe85e2d47b73096e19bc4c5fad26283173673c6c215291dafbeaf9d","b146d18fab487dd61667ae3a7c336464876666100aeb487bea67737cb1b23112c215291dafbeaf9d"};
        for(int i=0;i<families.length;i++)equal(hex(Protocol.payload(door(families[i]),1700000000,token)),vectors[i]);
        equal(Protocol.encrypt("{\"mobile\":\"13800000000\"}".getBytes(StandardCharsets.UTF_8)),"zyMCyXpYIQ6ZloIijtOtsGneXusPUIIQ906QYWGYvIo=");
        String unicode="门禁\n钥匙🔑";equal(new String(Protocol.decrypt(Protocol.encrypt(unicode.getBytes(StandardCharsets.UTF_8))),StandardCharsets.UTF_8),unicode);rejects(()->Protocol.decrypt("invalid"));
        rejects(()->door(1).validate(1700000000,false));Door expired=door(0);expired.expires=1700000000;rejects(()->expired.validate(1700000000,false));Door disabled=door(0);disabled.enabled=false;rejects(()->disabled.validate(1700000000,true));
        Door floor=door(0);floor.floor="32";rejects(()->floor.validate(1700000000,false));rejects(()->Protocol.payload(door(0),1700000000,new byte[0]));
        equal(Protocol.matches("1010203a1b2c3A",door(0)),true);equal(Protocol.matches("2010203ffffffA",door(0)),true);equal(Protocol.matches("1010203111111A",door(0)),false);equal(Protocol.matches("2999999a1b2c3A",door(0)),false);
        equal(SoundProtocol.authorization(door(0),1700000000),"07f3e5a6b");equal(SoundProtocol.authorization(door(100),1700000000),"40a885a6b");equal(SoundProtocol.crc("123456789".getBytes(StandardCharsets.UTF_8),true),0x4b37);
        String[] texts={"012345678","000000000","fffffffff","0706b1d2b","401234567"};int[][] codes={{9,0,1,2,3,4,5,6,7,8,9,7,15,14,18,8,6,0},{9,0,1,17,18,1,17,18,1,17,18,2,9,8,3,14,4,0},{9,0,16,17,18,16,17,18,16,17,18,7,11,16,10,3,2,0},{9,0,1,8,18,7,12,2,14,3,12,6,14,10,9,18,12,0},{9,0,5,1,2,3,4,5,6,7,8,11,3,17,15,10,1,0}};
        for(int i=0;i<texts.length;i++)equal(Arrays.toString(SoundProtocol.symbols(texts[i])),Arrays.toString(codes[i]));
        int[] bands={9000,12200,17000};String[] hashes={"127fe1a29de9b2cda6a9bb2f60409889063fef9546c00f61d3ee7a1168c420a0","24288fc2c682319e1ca7421531eb3f70a5d7c4dee0ed7fc7208e90122742aacd","28e9a878165c7306ed533db234a3d6dc5958c19507f91cc260f18a8323d0226a"};
        for(int i=0;i<3;i++){byte[] pcm=SoundProtocol.pcm("012345678",bands[i]);equal(pcm.length,112878);equal(hex(MessageDigest.getInstance("SHA-256").digest(pcm)),hashes[i]);}
        for(int type:new int[]{1,5,6,7,101})rejects(()->SoundProtocol.authorization(door(type),1700000000));rejects(()->SoundProtocol.symbols("not-hex!!"));
        equal(Door.parse(new JSONObject().put("owner_keys",new JSONArray().put(row()).toString())).size(),1);
        JSONObject group=row().put("type",5).put("ids",new JSONArray().put("41").put("42")).put("licenses",new JSONArray().put("a1b2c3").put("d4e5f6")).put("floor_stations",new JSONArray().put("01").put("02"));
        equal(Door.parse(new JSONObject().put("owner_keys",new JSONArray().put(group))).get(1).floor,"02");group.put("floor_stations",new JSONArray());rejects(()->Door.parse(new JSONObject().put("owner_keys",new JSONArray().put(group))));
        rejects(()->Door.parse(new JSONObject().put("owner_keys",new JSONArray().put(row()).put(row()))));equal(Door.parse(new JSONObject()).size(),0);
        DoorPreference old=new DoorPreference(new JSONObject("{\"alias\":\"南门\",\"favorite\":true,\"order\":2}"));equal(old.favorite,true);equal(old.alias,"南门");equal(old.band,12200);equal(old.transport,"bluetooth");old.transport="sound";old.band=9000;equal(new DoorPreference(old.json()).band,9000);
        List<String> paths=new ArrayList<>();KeybootAPI api=new KeybootAPI((path,body)->{paths.add(path);JSONObject f=fields(body);if(path.equals("auth")){equal(f.getString("device_id"),"test-device");return envelope(new JSONObject().put("code",100).put("token","session-only"));}
            if(path.equals("renew02")){equal(f.getString("token"),"session-only");return envelope(new JSONObject().put("code",100).put("token","rotated").put("servertime",1700000000).put("owner_keys",new JSONArray().put(row())));}
            if(path.equals("captcha01")){equal(new String(Protocol.decrypt(f.getString("timestamp")),StandardCharsets.UTF_8),"1700000000");return envelope(new JSONObject().put("code",100));}throw new AssertionError(path);});
        JSONObject account=api.login("13800000000","123456","test-device","Synthetic Android");equal(account.getString("token"),"session-only");JSONObject response=api.refresh(account,"Synthetic Android");equal(Door.parse(response).size(),1);equal(response.getString("token"),"rotated");equal(KeybootAPI.serverTime(response),1700000000L);api.sendCode("13800000000",1700000000);equal(paths.toString(),"[auth, renew02, captcha01]");
        KeybootAPI expiredAPI=new KeybootAPI((p,b)->envelope(new JSONObject().put("code","-400").put("msg","expired")));try{expiredAPI.refresh(account,"test");throw new AssertionError("Expected expired session");}catch(KeybootAPI.ServiceError e){equal(e.code,"-400");}
        rejects(()->new KeybootAPI((p,b)->envelope(new JSONObject().put("code",100))).login("13800000000","123456","device","test"));rejects(()->KeybootAPI.serverTime(new JSONObject()));rejects(()->api.sendCode("invalid",1700000000));
        System.out.println("PASS: "+passed+" assertions (BLE, AES, parser, API fixtures, sound authorization, symbols and three byte-exact PCM streams). No live requests or door commands.");
    }
}
