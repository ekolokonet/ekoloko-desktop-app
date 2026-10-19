package {
 import flash.display.Sprite;
 import flash.desktop.NativeApplication;
 import flash.events.UncaughtErrorEvent;
 import flash.filesystem.*;
 import flash.net.SharedObject;
 import flash.utils.*;
 import org.ekoloko.air.*;
 public class MobileReleaseTests extends Sprite {
  private var config:Object, count:int=0, selected:String="next", objectRequests:int=0;
  private var store:NativeReleaseStore, dir:File, pointerRequests:int=0;
  public function MobileReleaseTests() {
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("MOBILE_UPDATE_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   config=JSON.parse(read("config.json").toString());dir=File.createTempDirectory();
   SharedObject.getLocal("mobile-release-receipt-v1").clear();
   store=makeStore();
   store.useBundledManifest(config.old,function(path:String,entry:Object):ByteArray{return entry.sha256==config.old.assets["main.swf"].sha256 ? read("old.bin") : null;});
   store.refresh(function(m:Object):void {
    check(m==config.old && objectRequests==0,"installed_release_starts_without_download");
    store.checkUpdate(function(available:Boolean):void {
     check(available && store.manifest==config.old,"running_session_keeps_old_manifest");
     check(store.activateAvailableUpdate(),"signed_mobile_update_activates");
     check(store.manifest.mainVersion=="134","new_game_version_selected");
     store.load("shell.swf",function(b:ByteArray):void {
      check(objectRequests==0,"unchanged_shell_reuses_installed_pack");
      store.load("main.swf",function(b:ByteArray):void {
       check(objectRequests==1 && NativeServices.sha(b)==config.next.assets["main.swf"].sha256,"only_changed_main_downloaded");
       store.load("main.swf",function(b:ByteArray):void {
        check(objectRequests==1,"downloaded_object_cached");
        selected="desktop";reject("mobile_release_incompatible",function():void {
         selected="rollback";store.checkUpdate(function(a:Boolean):void { check(!a,"rollback_not_offered");
          selected="bad";reject("release_signature_invalid",function():void {
           selected="missing";reject("release_endpoint_missing",function():void {
            check(store.manifest.mainVersion=="134","failed_updates_preserve_active_release");
            selected="next";
            dir.resolvePath(config.next.assets["main.swf"].sha256+".swf").deleteFile();
            var called:Boolean=false;
            store.load("main.swf",function(b:ByteArray):void{called=true;},fail);store.cancel();
            setTimeout(function():void {
             check(!called,"cancelled_download_cannot_reach_retired_session");
             var fresh:NativeReleaseStore=makeStore();
             fresh.useBundledManifest(config.old,function(path:String,e:Object):ByteArray{return e.sha256==config.old.assets["main.swf"].sha256?read("old.bin"):null;});
             fresh.checkUpdate(function(a:Boolean):void {
              check(a && fresh.activateAvailableUpdate(),"restart_recovers_same_signed_generation");
              fresh.load("shell.swf",function(b:ByteArray):void {
               check(NativeServices.sha(b)==config.old.assets["main.swf"].sha256,"bundled_reuse_survives_restart");
               dir.deleteDirectory(true);SharedObject.getLocal("mobile-release-receipt-v1").clear();
               recoveryCases(0,function():void {
                missingCases(0,function():void{trace("MOBILE_UPDATE_PASS checks="+count);NativeApplication.nativeApplication.exit(0);});
               });
              },fail);
             },fail);
            },60);
           });
          });
         },fail);
        });
       },fail);
      },fail);
     },fail);
    },fail);
   },fail);
  }
  private function recoveryCases(index:int,next:Function):void {
   var modes:Array=["missing","unreadable","corrupt","remote_corrupt"];
   if(index>=modes.length){next();return;}
   var mode:String=modes[index],folder:File=File.createTempDirectory(),requests:int=0,completed:int=0;
   var recovery:NativeReleaseStore=new NativeReleaseStore("https://play.ekoloko.org",config.modulus,folder,function(path:String,limit:uint,done:Function,failed:Function):void {
    requests++;
    check(path=="objects/"+config.next.assets["main.swf"].sha256+".swf","recovery_uses_pinned_digest_"+mode);
    setTimeout(function():void{done(read(mode=="remote_corrupt"?"old.bin":"new.bin"));},0);
   },true);
   recovery.useBundledManifest(config.next,function(path:String,e:Object):ByteArray {
    if(mode=="unreadable")throw new Error("bundle_unreadable");
    return mode=="corrupt"?read("old.bin"):null;
   });
   recovery.load("not-in-approved-manifest.swf",function(b:ByteArray):void{throw new Error("unknown_asset_accepted");},function(e:Error):void {
    check(e.message=="asset_not_installed"&&requests==0,"unknown_asset_never_downloaded_"+mode);
   });
   check(recovery.read("main.swf")==null,"invalid_bundle_never_returned_"+mode);
   var settle:Function=function():void {
    if(++completed!=2)return;
    check(requests==1,"parallel_recovery_download_deduplicated_"+mode);
    if(mode=="remote_corrupt")check(recovery.read("main.swf")==null,"bad_remote_bytes_not_cached");
    else check(NativeServices.sha(recovery.read("main.swf"))==config.next.assets["main.swf"].sha256,"recovered_bytes_cached_"+mode);
    folder.deleteDirectory(true);recoveryCases(index+1,next);
   };
   var loaded:Function=function(b:ByteArray):void {
    check(mode!="remote_corrupt"&&NativeServices.sha(b)==config.next.assets["main.swf"].sha256,"approved_recovery_"+mode);settle();
   };
   var rejected:Function=function(e:Error):void {
    check(mode=="remote_corrupt"&&e.message=="asset_integrity","corrupt_download_rejected");settle();
   };
   recovery.load("main.swf",loaded,rejected);
   recovery.load("main.swf",loaded,rejected);
  }
  private function missingCases(index:int,next:Function):void {
   var modes:Array=["alias","newcode","corechange","oldercore"];
   if(index>=modes.length){next();return;}
   selected=modes[index];dir=File.createTempDirectory();var startRequests:int=pointerRequests,recovery:NativeReleaseStore=makeStore();
   var baseline:Object=config.next;
   if(selected=="oldercore"){baseline=JSON.parse(JSON.stringify(config.next));baseline.mainVersion="152";baseline.generation=0;}
   recovery.useBundledManifest(baseline,function(path:String,e:Object):ByteArray{return null;});
   var completed:int=0,mode:String=selected;
   var settle:Function=function():void{
    if(++completed!=2)return;
    check(recovery.manifest===baseline && recovery.manifest.assets["images/addition.swf"]==null,"active_manifest_unchanged_"+mode);
    check(pointerRequests-startRequests==1,"concurrent_metadata_lookup_deduplicated_"+mode);
    dir.deleteDirectory(true);missingCases(index+1,next);
   };
   var accepted:Function=function():void {
    check(mode=="alias","only_compiled_alias_admitted");
    recovery.load("images/addition.swf",function(bytes:ByteArray):void{check(NativeServices.sha(bytes)==config.next.assets["main.swf"].sha256,"signed_alias_bytes_verified");settle();},fail);
   };
   var rejected:Function=function(error:Error):void {
    var reason:String=mode=="newcode"?"asset_native_update_required":mode=="corechange"?"asset_core_update_required":"release_core_rollback_denied";
    check(error.message==reason,"rejected_"+mode);settle();
   };
   recovery.recoverMissing("images/addition.swf",accepted,rejected);
   recovery.recoverMissing("images/addition.swf",accepted,rejected);
  }
  private function reject(reason:String,next:Function):void {
   store.checkUpdate(function(a:Boolean):void{throw new Error("accepted_"+reason);},function(e:Error):void{check(e.message==reason,reason);next();});
  }
  private function makeStore():NativeReleaseStore {
   return new NativeReleaseStore("https://play.ekoloko.org",config.modulus,dir,function(path:String,limit:uint,done:Function,failed:Function):void {
    var mode:String=selected;
    setTimeout(function():void {
     if(mode=="missing"){failed(new Error("release_endpoint_missing"));return;}
     var name:String;
     if(path=="current.json"){pointerRequests++;name=mode+".pointer.json";}
     else if(path.indexOf("releases/")==0)name=mode+(path.indexOf(".sig")>=0?".sig":".json");
     else {objectRequests++;name="new.bin";}
     done(read(name));
    },0);
   },true);
  }
  private function fail(e:Error):void{throw e;}
  private function check(ok:Boolean,label:String):void{if(!ok)throw new Error(label);count++;trace("PASS "+label);}
  private function read(name:String):ByteArray{var b:ByteArray=new ByteArray(),s:FileStream=new FileStream();s.open(File.applicationDirectory.resolvePath(name),FileMode.READ);s.readBytes(b);s.close();b.position=0;return b;}
 }
}
