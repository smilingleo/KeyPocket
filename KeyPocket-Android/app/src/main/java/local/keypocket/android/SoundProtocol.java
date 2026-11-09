package local.keypocket.android;

import java.nio.*;
import java.util.*;

final class SoundProtocol {
    static final int RATE=44100;
    static final int[] ALPHA={1,2,4,8,3,6,12,11,5,10,7,14,15,13,9};
    static final int[] LOG={15,0,1,4,2,8,5,10,3,14,9,7,6,13,11,12};
    static String authorization(Door d,long time)throws Exception {
        d.validate(time,true);byte[] l=Protocol.reverse(Protocol.hex3(d.type==100?d.project:d.license));
        byte[] plain={l[0],l[1],l[2],l[0],l[1],l[2],(byte)(time%60),0};
        int crc=crc(Protocol.tea(plain,new int[]{101122824,17236489,134677250,17238274}),true);
        int floor=d.type==100?0x40:Integer.parseInt(d.floor.isEmpty()?"0":d.floor);
        return String.format(Locale.ROOT,"%02x%04x%03x",floor,crc,((time/60)%1440)*2+1);
    }
    static int crc(byte[] data,boolean modbus){
        int crc=65535;
        for(byte b:data){crc^=modbus?(b&255):(b&255)<<8;for(int i=0;i<8;i++)crc=modbus?((crc&1)!=0?(crc>>>1)^0xa001:crc>>>1):(((crc&0x8000)!=0?(crc<<1)^0x1021:crc<<1)&65535);}return crc;
    }
    static int multiply(int n,int power){return n==0?0:ALPHA[(LOG[n]+power)%15];}
    static int[] symbols(String hex)throws Exception {
        if(!hex.matches("[0-9a-fA-F]{9}"))throw new Exception("声波授权数据无效");
        byte[] data=new byte[15];for(int i=0;i<9;i++)data[i]=(byte)Character.digit(hex.charAt(i),16);
        int crc=crc(Arrays.copyOf(data,9),false);for(int i=0;i<4;i++)data[9+i]=(byte)((crc>>>(12-4*i))&15);
        int p0=0,p1=0;for(int i=12;i>=0;i--){int f=p1^data[i];p1=p0^multiply(f,5);p0=multiply(f,3);}data[13]=(byte)p0;data[14]=(byte)p1;
        int[] output=new int[18];output[0]=9;output[1]=0;int previous=-1,before=-1;
        for(int i=0;i<15;i++){int value=data[i];int next=value==previous?17:value==before?(previous==18?17:18):value;output[i+2]=next==17||next==18?next:next+1;before=previous;previous=next;}return output;
    }
    static byte[] pcm(String hex,int base)throws Exception {
        int[] codes=symbols(hex);int count=65*RATE/1000,padding=(int)(count*.08),ramp=(int)((count-2*padding)*.3),rampEnd=padding+ramp,fallEnd=count-padding;
        int amplitude=(int)(32768*.99);float slope=(float)amplitude/ramp;
        ByteBuffer out=ByteBuffer.allocate((10*RATE/1000+codes.length*count+RATE/10)*2).order(ByteOrder.LITTLE_ENDIAN);
        out.position(10*RATE/1000*2);
        for(int code:codes){float ratio=(float)(base+code*150)/RATE;float step=(float)((double)(ratio+ratio)*Math.PI),phase=0;
            for(int i=0;i<count;i++){int gain=i<padding||i>fallEnd+1?0:i>count-rampEnd+1?(int)((fallEnd-i)*slope):i<rampEnd?(int)((i-padding)*slope):amplitude;
                int sample=(int)(Math.sin((double)phase)*gain+.5);out.putShort((short)Math.max(-32768,Math.min(32767,sample)));phase+=step;}}
        return out.array();
    }
}
