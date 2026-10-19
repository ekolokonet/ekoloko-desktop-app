package {
    import flash.display.Sprite;
    import flash.desktop.NativeApplication;
    import flash.net.URLRequest;
    import flash.utils.setTimeout;
    import org.ekoloko.air.NativeNavigation;
    import org.ekoloko.air.NativeServices;
    import org.ekoloko.air.BuildInfo;
    public final class MobileLifecycleTests extends Sprite {
        private var checks:int=0;
        public function MobileLifecycleTests(){
            try {
                check(!MobileResumePolicy.restart(2000,true,true,false),"brief_connected_session_kept");
                check(MobileResumePolicy.restart(2000,true,false,false),"short_disconnected_session_restarts");
                check(!MobileResumePolicy.restart(29999,true,true,false),"threshold_before");
                check(MobileResumePolicy.restart(30000,true,true,false),"stale_socket_restarts");
                check(MobileResumePolicy.restart(60000,false,false,true),"interrupted_bootstrap_restarts");
                check(!MobileResumePolicy.restart(60000,false,false,false),"login_form_preserved");
                for each(var method:String in ["console.log","console.info","console.warn","console.error","console.debug","console.trace"])
                    check(NativeServices.externalCall(method,["test"])==null,"browser_console_is_nonfatal_"+method);
                var denied:Boolean=false;
                try{NativeServices.externalCall("console.info(); arbitrary()",[]);}catch(bridgeError:Error){denied=bridgeError.message=="native_bridge_method_denied";}
                check(denied,"arbitrary_bridge_method_still_denied");
                var before:uint=NativeServices.diagnostics().optionalAssetFailureCount;
                for(var asset:int=1;asset<=40;asset++)NativeServices.assetFailure("/ekoloko/items/HAT/HAT_"+asset+".swf",new Error("asset_not_installed"));
                NativeServices.assetFailure("/ekoloko/items/HAT/HAT_40.swf",new Error("asset_not_installed"));
                var failures:Object=NativeServices.diagnostics();
                check(failures.optionalAssetFailures.length==32&&failures.optionalAssetFailureCount==before+41,"asset_diagnostics_bounded");
                check(failures.optionalAssetFailures[31].count==2,"repeated_asset_failure_counted");
                check(failures.assetFailure==null&&failures.runtimeFailure==null,"optional_art_does_not_kill_session");
                NativeNavigation.internalLogin=false;
                check(NativeNavigation.plan("login.html").kind=="web","desktop_unchanged");
                NativeNavigation.internalLogin=true;
                for each(var url:String in ["login.html","./login.html","/ekoloko/login.html",BuildInfo.ORIGIN+"/ekoloko/login.html",BuildInfo.ORIGIN+"/ekoloko/login.html?language=iw",BuildInfo.ORIGIN.replace("https:","http:")+"/ekoloko/login.html"])
                    check(NativeNavigation.plan(url).kind=="reload","native_login");
                for each(url in ["https://example.com/ekoloko/login.html",BuildInfo.ORIGIN+"/ekoloko-web/forgotPassword.php",BuildInfo.ORIGIN+"/ekoloko/store.html",BuildInfo.ORIGIN+".example.com/ekoloko/login.html"])
                    check(NativeNavigation.plan(url).kind=="web","external_link_preserved");
                check(NativeNavigation.plan("javascript:alert(1)").kind=="unsupported","javascript_rejected");
                check(NativeNavigation.plan("javascript:window.location.reload(); void(0);").kind=="reload","legacy_reload");
                var called:int=0;
                NativeServices.reload=function():void{called++;};
                NativeNavigation.open(new URLRequest(BuildInfo.ORIGIN+"/ekoloko/login.html"),"_self");
                check(called==0,"restart_deferred_until_callback_returns");
                setTimeout(function():void{
                    try{check(called==1,"restart_dispatch_once");trace("MOBILE_LIFECYCLE_PASS checks="+checks);NativeApplication.nativeApplication.exit(0);}
                    catch(e:Error){failed(e);}
                },100);
            }catch(error:Error){failed(error);}
        }
        private function check(value:Boolean,name:String):void{if(!value)throw new Error(name);checks++;}
        private function failed(error:Error):void{trace("MOBILE_LIFECYCLE_FAIL "+error.message);NativeApplication.nativeApplication.exit(2);}
    }
}
