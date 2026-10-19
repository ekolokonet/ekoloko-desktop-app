package {
    import flash.display.Stage;
    import flash.events.Event;
    import flash.events.MouseEvent;
    import flash.events.TouchEvent;
    import flash.geom.Rectangle;
    public final class MobileTests {
        private static function check(value:Boolean,message:String):void {if(!value)throw new Error(message);}
        public static function run(stage:Stage):void {
            for each(var size:Array in [[667,375],[844,390],[932,430],[1024,768],[1194,834],[375,667],[390,844],[768,1024]]){
                var w:Number=size[0],h:Number=size[1],portrait:Boolean=h>w;
                var insets:Object={left:portrait?16:32,right:portrait?16:32,top:8,bottom:21};
                var normal:Object=MobileLayout.calculate(w,h,insets);
                check(normal.viewport.width==w,"world_full_width");
                check(normal.safe.containsRect(normal.toolbar),"toolbar_safe");
                check((normal.toolbar.width-24)/4>=44,"footer_hit_targets");
                var keyboard:Rectangle=new Rectangle(0,h-(portrait?290:180),w,portrait?290:180);
                var box:Object=MobileLayout.calculate(w,h,insets,keyboard,true);
                check(box.composer.bottom<=keyboard.y,"composer_keyboard_clearance");
                check(box.viewport.bottom<=keyboard.y,"camera_keyboard_clearance");
                check(box.viewport.bottom>=box.composer.bottom,"composer_overlays_room");
                check(normal.viewport.height==h,"room_continues_behind_original_dock");
                check(box.composer.width-116>=150,"native_input_width");
                check(normal.chat.width>=150,"original_chat_readable");
                var scale:Number=Math.max(MobileCamera.followScale(w,h),normal.viewport.height/600,w/960);
                for each(var position:Array in [[20,20],[480,300],[940,580]]){
                    var c:Object=MobileCamera.calculate(box.viewport,scale,position[0],position[1],false);
                    check(c.scale==scale,"keyboard_scale_stable");
                    check(new Rectangle(0,0,box.viewport.width,box.viewport.height).contains(c.x+position[0]*scale,c.y+position[1]*scale),"player_visible_at_edges");
                }
                var all:Object=MobileCamera.calculate(box.viewport,scale,480,300,true);
                check(all.x>=0&&all.y>=0&&all.x+960*all.scale<=box.viewport.width+.001&&all.y+600*all.scale<=box.viewport.height+.001,"overview_entire_room");
            }
            var view:Rectangle=new Rectangle(0,0,400,300);
            var still:Object=MobileCamera.follow(view,1,490,310,-280,-150,false);
            check(still.x==-280&&still.y==-150,"dead_zone_no_camera_jitter");
            var moved:Object=MobileCamera.follow(view,1,800,500,-280,-150,false);
            check(moved.x<-280&&moved.y<-150,"dead_zone_edge_follows");
            check(MobileCamera.followScale(844,390)==MobileCamera.followScale(390,844),"orientation_base_scale_equal");
            var stick:TouchJoystick=new TouchJoystick(function(x:Number,y:Number):void{});stage.addChild(stick);
            check(stick.alpha==0,"joystick_hidden_idle");
            stick.beginAt(100,180,7);
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_MOVE,true,false,7,false,160,180));
            check(stick.dx>.99&&stick.travelled,"dynamic_joystick_origin");
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_END,true,false,8));check(stick.dx>.99,"finger_ownership");
            stage.dispatchEvent(new Event(Event.DEACTIVATE));check(stick.dx==0&&stick.alpha==0,"background_hides_and_stops");
            stick.beginAt(100,180);stage.dispatchEvent(new MouseEvent(MouseEvent.MOUSE_MOVE,true,false,140,220));
            check(Math.abs(Math.sqrt(stick.dx*stick.dx+stick.dy*stick.dy)-1)<.001,"diagonal_speed_normalized");
            stick.setAvailable(false);check(stick.dx==0&&!stick.visible,"modal_stops_movement");
            stick.beginAt(100,180);check(stick.dx==0,"disabled_stays_inactive");stage.removeChild(stick);
            trace("MOBILE_8_LAYOUTS_DEAD_ZONE_AND_DYNAMIC_INPUT_PASS");
        }
    }
}
