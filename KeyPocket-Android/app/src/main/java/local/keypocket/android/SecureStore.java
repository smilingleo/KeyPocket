package local.keypocket.android;

import android.content.*;
import android.security.keystore.*;
import javax.crypto.*;
import javax.crypto.spec.*;
import java.security.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

final class SecureStore {
    private final SharedPreferences prefs;
    private static final String ALIAS="local.keypocket.account.v1";
    SecureStore(Context context){prefs=context.getSharedPreferences("secure-session",Context.MODE_PRIVATE);}
    private SecretKey key()throws Exception {
        KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);
        if(ks.containsAlias(ALIAS))return (SecretKey)ks.getKey(ALIAS,null);
        KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        g.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());return g.generateKey();
    }
    synchronized JSONObject read()throws Exception {
        String text=prefs.getString("account",null);if(text==null)return null;
        byte[] bytes=Base64.getDecoder().decode(text);if(bytes.length<29)throw new Exception("安全存储数据损坏，请重新登录");
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Arrays.copyOf(bytes,12)));
        return new JSONObject(new String(c.doFinal(Arrays.copyOfRange(bytes,12,bytes.length)),StandardCharsets.UTF_8));
    }
    synchronized void write(JSONObject account)throws Exception {
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key());byte[] data=c.doFinal(account.toString().getBytes(StandardCharsets.UTF_8)),iv=c.getIV(),out=new byte[iv.length+data.length];
        System.arraycopy(iv,0,out,0,iv.length);System.arraycopy(data,0,out,iv.length,data.length);
        if(!prefs.edit().putString("account",Base64.getEncoder().encodeToString(out)).commit())throw new Exception("无法保存登录状态");
    }
    synchronized void clear()throws Exception {if(!prefs.edit().remove("account").commit())throw new Exception("无法清除登录状态");}
}
