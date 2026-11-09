package local.keypocket.android;

import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.*;

final class Protocol {
    static final int[] AUTH={-1565027521,-2137322548,583228547,-420656679};
    static final int[] PAYLOAD={1783677750,1142738275,-1974410777,-484077794};
    static String encrypt(byte[] data)throws Exception{return Base64.getEncoder().encodeToString(aes(data,Cipher.ENCRYPT_MODE));}
    static byte[] decrypt(String text)throws Exception{return aes(Base64.getDecoder().decode(text.trim()),Cipher.DECRYPT_MODE);}
    static byte[] aes(byte[] data,int mode)throws Exception {
        Cipher c=Cipher.getInstance("AES/CBC/PKCS5Padding");
        c.init(mode,new SecretKeySpec("a49b75a814d505b048ab23546fcdba0d".getBytes(StandardCharsets.UTF_8),"AES"),new IvParameterSpec("bdc1946f73e6a3d7".getBytes(StandardCharsets.UTF_8)));
        return c.doFinal(data);
    }
    static byte[] hex3(String s)throws Exception {
        if(!s.matches("[a-fA-F0-9]{6}"))throw new Exception("门禁授权编码无效");
        byte[] b=new byte[3];for(int i=0;i<3;i++)b[i]=(byte)Integer.parseInt(s.substring(i*2,i*2+2),16);return b;
    }
    static byte[] reverse(byte[] a){byte[] b=a.clone();for(int i=0;i<b.length/2;i++){byte t=b[i];b[i]=b[b.length-1-i];b[b.length-1-i]=t;}return b;}
    static int word(byte[] b,int offset){return ByteBuffer.wrap(b,offset,4).order(ByteOrder.LITTLE_ENDIAN).getInt();}
    static byte[] tea(byte[] block,int[] k)throws Exception {
        if(block.length!=8||k.length!=4)throw new Exception("TEA 数据长度错误");
        int a=word(block,0),b=word(block,4),sum=0;
        for(int i=0;i<32;i++){sum+=0x9e3779b9;a+=((b<<4)+k[0])^(b+sum)^((b>>>5)+k[1]);b+=((a<<4)+k[2])^(a+sum)^((a>>>5)+k[3]);}
        return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putInt(a).putInt(b).array();
    }
    static byte[][] challenge(byte[] data)throws Exception {
        if(data.length!=18)throw new Exception("门禁挑战数据长度不兼容");
        byte[] token=reverse(Arrays.copyOfRange(data,8,16)),encrypted=reverse(tea(token,AUTH));
        byte[] frame=new byte[18];frame[0]=0x55;frame[1]=(byte)0xaa;frame[2]=0x12;frame[3]=(byte)0xc5;
        System.arraycopy(encrypted,0,frame,8,8);frame[16]=0x33;for(int i=0;i<17;i++)frame[17]^=frame[i];return new byte[][]{token,frame};
    }
    static byte[] plaintext(Door d,long timestamp)throws Exception {
        d.validate(timestamp,false);byte[] b=new byte[40];b[0]=b[1]=b[2]=1;b[3]=(byte)(d.type==100?1:d.type==3||d.type==5?5:0);
        System.arraycopy(hex3(d.project),0,b,5,3);System.arraycopy(hex3(d.license),0,b,9,3);
        long id=d.type==5?-1:d.keyID;for(int i=0;i<4;i++)b[12+i]=(byte)(id>>>(i*8));
        long mask=d.type==3?-1L:d.type==5?Long.parseUnsignedLong(d.floor,16):d.type==100?0xffffffff80000000L:1L<<(Integer.parseInt(d.floor)-1);
        for(int i=0;i<8;i++)b[27-i]=(byte)(mask>>>(i*8));for(int i=0;i<4;i++)b[28+i]=(byte)(timestamp>>>(i*8));b[32]=(byte)0xaa;return b;
    }
    static byte[] payload(Door d,long timestamp,byte[] token)throws Exception {
        if(token.length!=8)throw new Exception("门禁会话令牌长度错误");
        byte[] plain=plaintext(d,timestamp),out=new byte[40];int[] session={AUTH[0],AUTH[1],word(token,0),word(token,4)};
        for(int i=0;i<40;i+=8){byte[] block=tea(tea(reverse(Arrays.copyOfRange(plain,i,i+8)),PAYLOAD),session);System.arraycopy(block,0,out,i,8);}return out;
    }
    static boolean matches(String name,Door d) {
        if(name==null||name.length()!=14)return false;name=name.toLowerCase(Locale.ROOT);
        return name.startsWith("2"+d.project)||(d.type==100?name.startsWith("1"+d.project):name.equals("1"+d.project+d.license+"a"));
    }
}
