package local.keypocket.android;

import org.json.*;
import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class KeybootAPI {
    static final class ServiceError extends Exception { final String code; ServiceError(String code,String message){super(message);this.code=code;} }
    interface Transport { String post(String path,String body)throws Exception; }
    final Transport transport;
    KeybootAPI(){this((path,body)->{
        HttpURLConnection c=(HttpURLConnection)new URL("http://app.keyboot.com:8667/"+path).openConnection();
        c.setConnectTimeout(15000);c.setReadTimeout(15000);c.setInstanceFollowRedirects(false);c.setRequestMethod("POST");c.setDoOutput(true);
        c.setRequestProperty("Content-Type","application/x-www-form-urlencoded; charset=utf-8");byte[] bytes=body.getBytes(StandardCharsets.UTF_8);c.setFixedLengthStreamingMode(bytes.length);
        try {try(OutputStream os=c.getOutputStream()){os.write(bytes);}if(c.getResponseCode()!=200)throw new IOException("服务器请求失败（HTTP "+c.getResponseCode()+"）");
            try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedException("已取消");if(out.size()+n>8_000_000)throw new IOException("服务器返回数据过大");out.write(b,0,n);}return new String(out.toByteArray(),StandardCharsets.UTF_8);}
        }finally{c.disconnect();}
    });}
    KeybootAPI(Transport t){transport=t;}
    JSONObject request(String path,JSONObject fields)throws Exception {
        String body="jiami_data="+URLEncoder.encode(Protocol.encrypt(fields.toString().getBytes(StandardCharsets.UTF_8)),"UTF-8");
        JSONObject result=new JSONObject(new String(Protocol.decrypt(transport.post(path,body)),StandardCharsets.UTF_8));
        String code=Door.str(result,"code");if(!"100".equals(code))throw new ServiceError(code,Door.str(result,"msg").isEmpty()?"请求失败（"+code+"）":Door.str(result,"msg"));return result;
    }
    void sendCode(String mobile,long now)throws Exception {
        if(!mobile.matches("1[3-9][0-9]{9}"))throw new Exception("请输入有效的中国大陆手机号");
        request("captcha01",new JSONObject().put("mobile",mobile).put("timestamp",Protocol.encrypt(Long.toString(now).getBytes(StandardCharsets.UTF_8))));
    }
    JSONObject login(String mobile,String code,String device,String model)throws Exception {
        if(!mobile.matches("1[3-9][0-9]{9}")||code.trim().isEmpty())throw new Exception("请输入有效手机号和验证码");
        JSONObject r=request("auth",new JSONObject().put("mobile",mobile).put("captcha",code).put("device_id",device).put("model",model));
        String token=Door.str(r,"token");if(token.isEmpty())throw new Exception("登录响应缺少令牌");
        return new JSONObject().put("mobile",Door.str(r,"mobile").isEmpty()?mobile:Door.str(r,"mobile")).put("token",token).put("device_id",device);
    }
    JSONObject refresh(JSONObject account,String model)throws Exception {return request("renew02",params(account).put("model",model).put("appversion","4.5.0"));}
    String verify(Door d,JSONObject account)throws Exception {return Door.str(request("key_verification",params(account).put("key_id",Long.toString(d.keyID)).put("license",d.project)),"token");}
    static JSONObject params(JSONObject a)throws Exception {return new JSONObject().put("mobile",a.getString("mobile")).put("token",a.getString("token")).put("device_id",a.getString("device_id"));}
    static long serverTime(JSONObject r)throws Exception {long time=Long.parseLong(Door.str(r,"servertime"));if(time<=0)throw new Exception("缺少服务器时间，请重试");return time;}
}
