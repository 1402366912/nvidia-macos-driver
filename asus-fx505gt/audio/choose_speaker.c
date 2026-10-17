#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void inspectDefault(AudioObjectPropertySelector which, AudioObjectPropertyScope scope) {
 AudioObjectPropertyAddress p={which,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};AudioDeviceID d=0;UInt32 n=sizeof(d);OSStatus r=AudioObjectGetPropertyData(kAudioObjectSystemObject,&p,0,NULL,&n,&d);printf("default=%u status=%d device=%u\n",which,r,d);if(r||!d)return;
 CFStringRef name=NULL;n=sizeof(name);p=(AudioObjectPropertyAddress){kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,0};
 if(!AudioObjectGetPropertyData(d,&p,0,NULL,&n,&name)){char text[512]={0};CFStringGetCString(name,text,sizeof(text),kCFStringEncodingUTF8);CFRelease(name);printf("name=%s\n",text);}
 for(unsigned ch=0;ch<3;ch++){
  UInt32 mute=0;n=sizeof(mute);p=(AudioObjectPropertyAddress){kAudioDevicePropertyMute,scope,ch};r=AudioObjectGetPropertyData(d,&p,0,NULL,&n,&mute);printf("channel=%u mute_status=%d mute=%u",ch,r,mute);
  Float32 volume=0;n=sizeof(volume);p.mSelector=kAudioDevicePropertyVolumeScalar;r=AudioObjectGetPropertyData(d,&p,0,NULL,&n,&volume);printf(" gain_status=%d gain=%.4f\n",r,volume);
 }
}
int main(int argc,char **argv) {
 if(argc==2&&!strcmp(argv[1],"--inspect")){inspectDefault(kAudioHardwarePropertyDefaultInputDevice,kAudioDevicePropertyScopeInput);inspectDefault(kAudioHardwarePropertyDefaultOutputDevice,kAudioDevicePropertyScopeOutput);return 0;}
 AudioObjectPropertyAddress p={kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};UInt32 bytes=0;
 OSStatus r=AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&p,0,NULL,&bytes);if(r)return 1;
 AudioDeviceID *devices=malloc(bytes);r=AudioObjectGetPropertyData(kAudioObjectSystemObject,&p,0,NULL,&bytes,devices);if(r){free(devices);return 2;}
 AudioDeviceID speaker=kAudioObjectUnknown;unsigned matches=0;
 for(unsigned i=0;i<bytes/sizeof(*devices);i++){
  CFStringRef name=NULL;UInt32 n=sizeof(name);AudioObjectPropertyAddress q={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
  if(AudioObjectGetPropertyData(devices[i],&q,0,NULL,&n,&name))continue;
  char text[512]={0};CFStringGetCString(name,text,sizeof(text),kCFStringEncodingUTF8);CFRelease(name);printf("device=%u name=%s\n",devices[i],text);
  if(strstr(text,"Speaker (Analog)")){speaker=devices[i];matches++;}
 }free(devices);if(matches!=1)return 3;
 AudioObjectPropertySelector selectors[]={kAudioHardwarePropertyDefaultOutputDevice,kAudioHardwarePropertyDefaultSystemOutputDevice};
 for(unsigned i=0;i<2;i++){
  p=(AudioObjectPropertyAddress){selectors[i],kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};r=AudioObjectSetPropertyData(kAudioObjectSystemObject,&p,0,NULL,sizeof(speaker),&speaker);if(r)return 4;
  AudioDeviceID check=0;UInt32 n=sizeof(check);r=AudioObjectGetPropertyData(kAudioObjectSystemObject,&p,0,NULL,&n,&check);printf("default_selector=%u status=%d device=%u\n",selectors[i],r,check);if(r||check!=speaker)return 5;
 }
 UInt32 mute=0;p=(AudioObjectPropertyAddress){kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};
 if(AudioObjectHasProperty(speaker,&p)){r=AudioObjectSetPropertyData(speaker,&p,0,NULL,sizeof(mute),&mute);printf("speaker_unmute_status=%d\n",r);}
 return 0;
}
