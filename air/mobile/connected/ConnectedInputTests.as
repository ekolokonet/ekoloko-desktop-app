package {
    import flash.display.Sprite;import flash.display.DisplayObjectContainer;
    import flash.desktop.NativeApplication;
    import flash.geom.Rectangle;
    public final class ConnectedInputTests extends Sprite {
        public function ConnectedInputTests() {
            try {
                var calls:Array=[],blocked:Boolean=false,inGame:Boolean=false,walkable:Boolean=true;
                var player:Object={x:300,y:200,getPlayerId:function():int{return 123;}};
                var room:Object={active:true,walkPlayer:function(id:int,x:int,y:int,run:Boolean):int{calls.push(["walk",id,x,y,run]);return 4;}};
                var main:Object={room:room,myPlayer:player,
                    isMenuOpened:function():Boolean{return blocked;},isIninWorldGame:function():Boolean{return inGame;},
                    IsWalkable:function(x:int,y:int):Boolean{return walkable;},
                    SetMyPositionVariables:function(x:int,y:int,face:int,run:Boolean):void{calls.push(["position",x,y,face,run]);}};
                check(ConnectedGameInput.move(main,1,0),"move");
                check(calls.length==2&&calls[0][0]=="walk"&&calls[1][0]=="position"&&calls[1][3]==4,"existing_navigation_order");
                check(calls[0][2]==355&&calls[0][3]==200&&!calls[0][4],"bounded_walk_not_run");
                calls=[];blocked=true;check(!ConnectedGameInput.move(main,1,0)&&calls.length==0,"menu_gate");blocked=false;
                inGame=true;check(!ConnectedGameInput.move(main,1,0)&&calls.length==0,"minigame_gate");inGame=false;
                room.active=false;check(!ConnectedGameInput.move(main,1,0)&&calls.length==0,"transition_gate");room.active=true;
                walkable=false;check(!ConnectedGameInput.move(main,1,0)&&calls.length==0,"walk_mask");walkable=true;
                check(!ConnectedGameInput.move(main,0,0)&&calls.length==0,"idle");
                player.x=959;check(!ConnectedGameInput.move(main,1,0)&&calls.length==0,"room_bounds");
                player.x=300;check(ConnectedGameInput.move(main,1,1),"diagonal");
                check(calls[0][2]-300==calls[0][3]-200&&calls[0][2]-300<55,"normalized_diagonal");
                var view:Rectangle=new Rectangle(0,0,390,600),camera:Object=MobileCamera.calculate(view,1,480,300,false),before:Object;
                var restX:Number=camera.x,restY:Number=camera.y;
                for(var i:int=0;i<120;i++){camera=MobileCamera.smoothFollow(view,1,480+(i%2?2:-2),300,camera,42);check(camera.x==restX&&camera.y==restY,"camera_idle_deadzone");}
                for(i=0;i<180;i++){
                    before=camera;camera=MobileCamera.smoothFollow(view,1,Math.min(959,480+i*4),300,camera,i%3?42:17);
                    check(camera.x<=before.x&&camera.x>=390-960&&camera.y==0,"camera_monotonic_right_and_bounds");
                }
                for(i=0;i<180;i++){
                    before=camera;camera=MobileCamera.smoothFollow(view,1,0,300,camera,42);
                    check(camera.x>=before.x&&camera.x<=0,"camera_reverse_no_oscillation");
                }
                before=camera;camera=MobileCamera.smoothFollow(view,1,959,300,camera,0);check(camera.x==before.x,"camera_same_frame_idempotent");
                var dockCases:int=0;
                for each(var width:Number in [375,390,667,844,1024])for each(var hidden:Boolean in [false,true]){
                    var left:Array=hidden?["settings","pet","emote"]:["settings","home","pet","emote"];
                    var right:Array=["hand","key","friends","map","bag"],safe:Rectangle=new Rectangle(12,8,width-24,700);
                    var layout:Object=ConnectedDockLayout.calculate(safe,left,right),rects:Array=[layout.chat];
                    check(layout.chat.width>=260&&safe.containsRect(layout.chat),"readable_chat_width");
                    for each(var id:String in left.concat(right)){
                        var slot:Rectangle=layout.slots[id];check(slot.width==48&&slot.height==48&&safe.containsRect(slot),"consistent_touch_target");
                        for each(var previous:Rectangle in rects)check(!slot.intersects(previous),"dock_no_overlap");rects.push(slot);
                    }
                    check(hidden?layout.slots.home==null:layout.slots.home!=null,"hidden_control_releases_space");dockCases++;
                }
                var nativeBox:DisplayObjectContainer=new OriginalUI.Chat();GameArtwork.stopTree(nativeBox);
                var opening:Rectangle=NativeChatGeometry.opening(nativeBox.getChildAt(0));
                check(opening!=null&&opening.width>100&&opening.height>=15,"native_white_opening_detected");
                trace("CHAT_WHITE_OPENING "+opening);
                NativeChatBoundsTests.run(this);
                var responsiveCases:int=0;
                for each(var size:Array in [[375,350],[390,812],[667,375],[844,358],[1024,736]]){
                    for each(var bounds:Rectangle in [new Rectangle(-20,-7,454,342),new Rectangle(32,-24,500,451),new Rectangle(-1,-11,515,420)]){
                        var full:Object=MobileDrawerLayout.calculate(size[0],size[1],size[1],bounds);
                        var keyboard:Object=MobileDrawerLayout.calculate(size[0],size[1],size[1]/2,bounds);
                        check(full.x==keyboard.x&&full.y==0&&keyboard.y==0&&full.scale==keyboard.scale,"drawer_anchor_and_size_survive_keyboard");
                        check(full.x>=0&&full.x+full.width<=size[0]&&full.height<=size[1],"drawer_fits_screen");responsiveCases++;
                    }
                    for each(var count:int in [1,2,3,12])for each(var pages:int in [1,3]){
                        var server:Object=MobileServerLayout.calculate(size[0],size[1],count,pages);
                        var first:Rectangle=server.slots[0];
                        var single:Rectangle=MobileServerLayout.calculate(size[0],size[1],1,pages).slots[0];
                        check(first.equals(single)&&first.x==0&&first.y==0,"server_stable_native_top_left_anchor");
                        var cover:Number=Math.max(size[0]/960,size[1]/600),offset:Number=(size[0]-960*cover)/2;
                        check(server.area.x>=offset+200*cover&&server.area.right<=offset+752*cover,"server_cards_inside_parchment");
                        for each(var card:Rectangle in server.slots)check(card.x>=0&&card.right<=server.area.width&&card.height>=44,"readable_server_touch_target");responsiveCases++;
                    }
                    var edit:Object=MobileLayout.calculate(size[0],size[1],{left:12,right:12,top:8,bottom:12},null,true);
                    check(edit.viewport.bottom==size[1],"composer_overlays_full_room");
                }
                trace("RESPONSIVE_PASS cases="+responsiveCases);
                trace("CONNECTED_INPUT_PASS navigation_checks=11 camera_frames=481 dock_cases="+dockCases+" no_network=true");NativeApplication.nativeApplication.exit(0);
            }catch(e:Error){trace("CONNECTED_INPUT_FAIL "+e.message);NativeApplication.nativeApplication.exit(1);}
        }
        private function check(ok:Boolean,name:String):void {if(!ok)throw new Error(name);}
    }
}
