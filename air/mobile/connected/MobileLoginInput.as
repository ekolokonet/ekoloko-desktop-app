package {
    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.events.Event;
    import flash.events.KeyboardEvent;
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.system.Capabilities;
    import org.ekoloko.air.NativeServices;

    /** Commit the native iOS editor before the legacy CLICK handler reads it. */
    public final class MobileLoginInput {
        private var form:DisplayObjectContainer;
        private static const RESULTS:Array=["bad_user_pass","uknown_error","network_security_block",
            "login_ok","login_ok_mod","login_ok_newbie","login_ok_ranger","not_activated",
            "user_banned1","user_banned7","user_banned_forever"];
        public function MobileLoginInput(value:DisplayObjectContainer) {
            form=value;
            for each(var type:String in RESULTS)form.addEventListener(type,result);
            if(Capabilities.version.indexOf("IOS")==0){
                form.addEventListener(MouseEvent.MOUSE_DOWN,pressed,true,2000);
                form.addEventListener(TouchEvent.TOUCH_BEGIN,pressed,true,2000);
                form.addEventListener(KeyboardEvent.KEY_DOWN,keyDown,true,2000);
            }
        }
        private function result(e:Event):void {
            // Fixed event codes only. Never inspect or record credential values.
            NativeServices.report({stage:"login_result",reasonCode:e.type});
        }
        private function pressed(e:Event):void {
            var target:DisplayObject=e.target as DisplayObject;
            while(target&&target!=form){
                if(target==Object(form).loginBut){commit();return;}
                target=target.parent;
            }
        }
        private function keyDown(e:KeyboardEvent):void {if(e.keyCode==13)commit();}
        private function commit():void {
            if(form.stage&&(form.stage.focus==Object(form).usr||form.stage.focus==Object(form).pass)){
                form.stage.focus=null;
                NativeServices.report({stage:"login_input",reasonCode:"native_editor_blurred_before_submit"});
            }
        }
        public function dispose():void {
            for each(var type:String in RESULTS)form.removeEventListener(type,result);
            form.removeEventListener(MouseEvent.MOUSE_DOWN,pressed,true);
            form.removeEventListener(TouchEvent.TOUCH_BEGIN,pressed,true);
            form.removeEventListener(KeyboardEvent.KEY_DOWN,keyDown,true);
        }
    }
}
