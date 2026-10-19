package {
    import flash.desktop.NativeApplication;
    import flash.display.*;
    import flash.events.*;
    import flash.geom.*;
    import flash.filesystem.*;
    import flash.text.StageText;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;
    import flash.utils.*;

    [SWF(width="844",height="390",frameRate="30",backgroundColor="#153C31")]
    public final class MobileLab extends Sprite {
        private var scene:MobileScene=new MobileScene();
        private var viewport:Sprite=new Sprite();
        private var hud:Sprite=new Sprite();
        private var history:RecentMessages=new RecentMessages();
        private var composer:Sprite=new Sprite();
        private var modal:Sprite=new Sprite();
        private var joystick:TouchJoystick;
        private var input:StageText;
        private var editing:Boolean=false,overview:Boolean=false,rendering:Boolean=false;
        private var modalName:String="";
        private var box:Object;
        private var zoom:Number=1;
        private var vx:Number=0,vy:Number=0;
        private var target:Point;
        private var previous:int;
        private var messageClock:Number=0;
        private var feedClock:Number=0;
        private var historyScroll:Number=0;
        private var demoMessage:int=0;
        private var touches:Object={};
        private var pinchDistance:Number=0,pinchZoom:Number=1;
        private var lastTouch:int=-1000;
        private var suppressClick:Boolean=false;
        private var messages:Array=[];
        private var walked:Boolean=false,chatted:Boolean=false,looked:Boolean=false;
        private var cameraButton:Sprite;
        private var argv:Array;

        public function MobileLab() {
            stage.scaleMode=StageScaleMode.NO_SCALE;stage.align=StageAlign.TOP_LEFT;
            Multitouch.inputMode=MultitouchInputMode.TOUCH_POINT;
            viewport.addChild(scene);addChild(viewport);addChild(hud);
            joystick=new TouchJoystick(function(x:Number,y:Number):void {vx=x;vy=y;if(x||y)target=null;});
            addChild(joystick);addChild(history);addChild(composer);addChild(modal);
            scene.onInteract=function(kind:String):void {showPanel(kind);};
            viewport.addEventListener(MouseEvent.CLICK,walkTo);
            viewport.addEventListener(MouseEvent.MOUSE_DOWN,mouseStart);
            viewport.addEventListener(TouchEvent.TOUCH_BEGIN,touchStart);
            stage.addEventListener(TouchEvent.TOUCH_MOVE,touchMove);
            stage.addEventListener(TouchEvent.TOUCH_END,touchEnd);
            viewport.addEventListener(MouseEvent.MOUSE_WHEEL,function(e:MouseEvent):void {changeZoom(zoom+e.delta*.05);});
            input=new StageText();input.visible=false;input.fontFamily="Arial";input.fontWeight="bold";input.fontSize=18;input.color=0;
            input.locale="he-IL";input.textAlign="right";input.returnKeyLabel="done";input.maxChars=160;input.autoCorrect=true;
            input.addEventListener(KeyboardEvent.KEY_DOWN,inputKey);
            input.addEventListener(SoftKeyboardEvent.SOFT_KEYBOARD_ACTIVATE,resize);
            input.addEventListener(SoftKeyboardEvent.SOFT_KEYBOARD_DEACTIVATE,resize);
            stage.addEventListener(Event.RESIZE,resize);
            NativeApplication.nativeApplication.addEventListener(Event.DEACTIVATE,deactivate);
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE,invoke);
            loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void {
                trace("MOBILE_RUNTIME_ERROR "+e.error);if(rendering)NativeApplication.nativeApplication.exit(2);
            });
            addMessage("נועה · דוגמה","נפגשים ליד היתקליף?",650);
            addMessage("אורי · דוגמה","אני בדרך!",280);
            addEventListener(Event.ENTER_FRAME,frame);previous=getTimer();resize();
        }
        private function invoke(e:InvokeEvent):void {
            argv=e.arguments;
            if(argv.indexOf("--show-history")>=0&&!history.visible)history.toggle();
            if(argv.indexOf("--ui-probe")>=0){
                var menu:DisplayObject=new OriginalUI.Menu();GameArtwork.stopTree(menu);OriginalUI.dump(menu);
                var panel:DisplayObject=new OriginalUI.QuestPanel();GameArtwork.stopTree(panel);OriginalUI.dump(panel);
                var chat:DisplayObject=new OriginalUI.Chat();GameArtwork.stopTree(chat);OriginalUI.dump(chat);
                removeChildren();addChild(menu);menu.scaleX=menu.scaleY=.8;menu.y=-80;
                snapshot("original-menu");removeChildren();addChild(panel);panel.scaleX=panel.scaleY=.65;panel.y=62;
                snapshot("original-quest");
                NativeApplication.nativeApplication.exit(0);return;
            }
            if(argv.indexOf("--self-test")>=0){
                try{MobileTests.run(stage);history.verify();testChat();testMenu();testGestures();testRotation();}
                catch(error:Error){trace("MOBILE_TESTS_FAIL "+error.message);NativeApplication.nativeApplication.exit(1);}
            }
            if(argv.indexOf("--render")>=0){
                rendering=true;
                addMessage("אני · מקומי","שלום לכולם",400);
                snapshotIcons();
                setTimeout(function():void {
                    snapshot("room");history.toggle();snapshot("history");history.toggle();toggleCamera();snapshot("overview");toggleCamera();
                    showPanel("inventory");snapshot("inventory");closePanel();
                    openChat();input.text="שלום לכולם";
                    setTimeout(function():void {
                        snapshot("keyboard");history.toggle();snapshot("keyboard-history");history.toggle();toggleCamera();snapshot("keyboard-overview");toggleCamera();
                        closeChat();joystick.beginAt(box.safe.x+80,box.viewport.bottom-80);snapshot("joystick");joystick.reset();
                        NativeApplication.nativeApplication.exit(0);
                    },400);
                },400);
            }
        }
        private function insets():Object {
            var portrait:Boolean=stage.stageHeight>stage.stageWidth;
            return {left:portrait?16:32,right:portrait?16:32,top:8,bottom:21};
        }
        private function label(parent:Sprite,text:String,x:Number,y:Number,width:Number,size:Number=16,color:uint=0xffffff):void {
            var l:MobileLabel=new MobileLabel(text,width,size,color,"right");l.x=x;l.y=y;parent.addChild(l);
        }
        private function iconButton(parent:Sprite,id:String,x:Number,y:Number,action:Function):Sprite {
            var b:Sprite=OriginalUI.actionButton(id,action);b.x=x;b.y=y;parent.addChild(b);return b;
        }
        private function resize(e:Event=null):void {
            if(!input)return;
            joystick.reset();touches={};pinchDistance=0;
            var keyboard:Rectangle=stage.softKeyboardRect;
            var simulated:Boolean=editing&&keyboard.height==0;
            if(simulated){var kh:Number=stage.stageHeight>stage.stageWidth?290:180;keyboard=new Rectangle(0,stage.stageHeight-kh,stage.stageWidth,kh);}
            box=MobileLayout.calculate(stage.stageWidth,stage.stageHeight,insets(),editing?keyboard:null,editing);
            viewport.scrollRect=new Rectangle(0,0,box.viewport.width,box.viewport.height);
            updateCamera(0,true);drawHUD();drawFeed();
            var historyTop:Number=editing&&!box.portrait?4:70;
            history.fit(new Rectangle(box.safe.x,historyTop,box.safe.width,(editing?box.composer.y:box.toolbar.y)-historyTop-4));
            joystick.setAvailable(!editing&&modalName=="");
            composer.removeChildren();composer.graphics.clear();composer.visible=editing;
            if(editing){
                if(simulated){
                    composer.graphics.beginFill(0x24342e);composer.graphics.drawRect(keyboard.x,keyboard.y,keyboard.width,keyboard.height);composer.graphics.endFill();
                    label(composer,"הדמיית שטח המקלדת",20,keyboard.y+40,keyboard.width-40,18);
                    label(composer,"אפשר להקליד עם מקלדת המק",20,keyboard.y+72,keyboard.width-40,14,0xc1d3c8);
                }
                var r:Rectangle=box.composer;
                var bg:Sprite=OriginalUI.chatBackground(r.width,r.height);bg.x=r.x;bg.y=r.y;composer.addChild(bg);
                var submit:Sprite=OriginalUI.submit(send);submit.x=r.right-44;submit.y=r.y;composer.addChild(submit);
                iconButton(composer,"close",r.x,r.y-1,closeChat);
                var inputRect:Rectangle=NativeChatGeometry.inputBounds(bg,this,submit.x);
                inputRect.left=Math.max(inputRect.left,Math.ceil(r.x+54));
                input.viewPort=inputRect;input.stage=stage;input.visible=!inputRect.isEmpty();
            }else{input.visible=false;input.stage=null;}
            if(modalName!="")drawPanel();
        }
        private function drawHUD():void {
            hud.removeChildren();hud.graphics.clear();
            label(hud,"בדיקה מקומית",box.safe.x,0,box.safe.width,10);
            var x:Number=box.safe.right;
            cameraButton=iconButton(hud,overview?"follow":"overview",x-48,18,toggleCamera);
            iconButton(hud,"messages",x-104,18,function():void{history.toggle();});
            iconButton(hud,"rotate",editing&&!box.portrait?x-160:box.safe.x,18,rotate);
            if(!box.portrait&&!editing){
                iconButton(hud,"zoomIn",box.safe.x+56,18,function():void{changeZoom(zoom+.15);});
                iconButton(hud,"zoomOut",box.safe.x+112,18,function():void{changeZoom(zoom-.15);});
            }
            if(!editing){
                var extras:Array=["help","paperBut","pioStore"];
                for each(var extra:String in extras){
                    var extraIcon:Sprite=OriginalUI.icon(extra,menuAction(extra));extraIcon.x=box.safe.right-48;
                    extraIcon.y=76+extras.indexOf(extra)*52;hud.addChild(extraIcon);
                }
                for(var i:int=0;i<OriginalUI.DOCK.length;i++){
                    var id:String=OriginalUI.DOCK[i],icon:Sprite=OriginalUI.icon(id,menuAction(id));hud.addChild(icon);
                    if(box.stacked){
                        var cols:int=5,step:Number=box.safe.width/cols;
                        icon.x=box.safe.x+(i%cols)*step+(step-48)/2;icon.y=box.toolbar.y+int(i/cols)*52;
                    }else{
                        icon.x=i<4?box.safe.x+i*48:box.safe.right-(OriginalUI.DOCK.length-i)*48;
                        icon.y=box.toolbar.y;
                    }
                }
                var r:Rectangle=box.chat;
                var chat:Sprite=OriginalUI.chatBackground(r.width,44);chat.x=r.x;chat.y=r.y;hud.addChild(chat);
                var hintRect:Rectangle=NativeChatGeometry.inputBounds(chat,this,r.right-44);
                var hint:Sprite=new Sprite();hint.x=hintRect.x;hint.y=hintRect.y;
                hint.graphics.beginFill(0,0);hint.graphics.drawRect(0,0,hintRect.width,hintRect.height);hint.graphics.endFill();
                label(hint,input.text.length?input.text:(r.width<240?"כתבו כאן":"לחצו כאן כדי לכתוב"),0,Math.max(0,(hintRect.height-19)/2),hintRect.width,15,0x345a73);
                hint.scrollRect=new Rectangle(0,0,hintRect.width,hintRect.height);hint.mouseChildren=false;hint.buttonMode=true;hint.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{openChat();});hud.addChild(hint);
                var sendButton:Sprite=OriginalUI.submit(openChat);sendButton.x=r.right-44;sendButton.y=r.y;hud.addChild(sendButton);
            }
        }
        private function menuAction(id:String):Function {
            return function():void {
                if(id=="myData")showPanel("inventory");
                else if(id=="quests")showPanel("tasks");
                else showPanel(id);
            };
        }
        private function drawFeed():void {history.update(messages);}
        private function addMessage(name:String,text:String,x:Number=-1):void {
            messages.push({name:name,text:text,x:x,own:name=="אני · מקומי"});if(messages.length>200)messages.shift();scene.speak(x,text);drawFeed();
        }
        private function openChat():void {closePanel();editing=true;target=null;joystick.reset();scene.move(0,0,0);resize();input.assignFocus();}
        private function closeChat():void {editing=false;stage.focus=null;resize();}
        private function send():void {
            var text:String=input.text.replace(/^\s+|\s+$/g,"");if(!text.length)return;
            addMessage("אני · מקומי",text);input.text="";chatted=true;input.assignFocus();
        }
        private function inputKey(e:KeyboardEvent):void {if(e.keyCode==13){e.preventDefault();send();}if(e.keyCode==27)closeChat();}
        private function toggleCamera():void {overview=!overview;looked=true;updateCamera(0,true);drawHUD();drawFeed();if(editing)input.assignFocus();}
        private function changeZoom(value:Number):void {zoom=Math.max(.75,Math.min(1.65,value));overview=false;updateCamera(0,true);drawHUD();if(editing)input.assignFocus();}
        private function rotate():void {stage.setOrientation(stage.stageWidth>stage.stageHeight?StageOrientation.DEFAULT:StageOrientation.ROTATED_RIGHT);}
        private function updateCamera(dt:Number,snap:Boolean=false):void {
            if(!box)return;
            var normal:Object=MobileLayout.calculate(stage.stageWidth,stage.stageHeight,insets());
            var scale:Number=Math.max(MobileCamera.followScale(stage.stageWidth,stage.stageHeight),normal.viewport.width/960,normal.viewport.height/600)*zoom;
            var focusY:Number=scene.player.y-48;
            var c:Object=overview?MobileCamera.calculate(box.viewport,scale,scene.player.x,focusY,true):
                MobileCamera.follow(box.viewport,scale,scene.player.x,focusY,scene.x,scene.y,snap);
            var mix:Number=snap?1:1-Math.exp(-10*dt);scene.scaleX=scene.scaleY=c.scale;
            scene.x+=(c.x-scene.x)*mix;scene.y+=(c.y-scene.y)*mix;
        }
        private function interactive(target:DisplayObject):Boolean {
            for(var o:DisplayObject=target;o&&o!=viewport;o=o.parent)if(o.name=="resident")return true;
            return false;
        }
        private function mouseStart(e:MouseEvent):void {
            if(getTimer()-lastTouch<500||editing||modalName!=""||interactive(e.target as DisplayObject))return;
            if(e.stageX<stage.stageWidth*.45&&e.stageY>80){joystick.beginAt(e.stageX,e.stageY);}
        }
        private function touchStart(e:TouchEvent):void {
            if(modalName!=""||interactive(e.target as DisplayObject))return;
            lastTouch=getTimer();touches[e.touchPointID]=new Point(e.stageX,e.stageY);
            var points:Array=touchPoints();
            if(points.length==2){pinchDistance=Point.distance(points[0],points[1]);pinchZoom=zoom;joystick.reset();target=null;suppressClick=true;}
            else if(!editing&&e.stageX<stage.stageWidth*.45&&e.stageY>80)joystick.beginAt(e.stageX,e.stageY,e.touchPointID);
        }
        private function touchPoints():Array {var a:Array=[];for each(var p:Point in touches)a.push(p);return a;}
        private function touchMove(e:TouchEvent):void {
            if(!touches.hasOwnProperty(e.touchPointID))return;
            lastTouch=getTimer();touches[e.touchPointID]=new Point(e.stageX,e.stageY);
            var points:Array=touchPoints();
            if(points.length==2&&pinchDistance>0)changeZoom(pinchZoom*Point.distance(points[0],points[1])/pinchDistance);
        }
        private function touchEnd(e:TouchEvent):void {lastTouch=getTimer();delete touches[e.touchPointID];if(touchPoints().length<2)pinchDistance=0;}
        private function walkTo(e:MouseEvent):void {
            if(modalName!="")return;
            if(suppressClick||joystick.travelled){suppressClick=false;joystick.travelled=false;return;}
            if(editing){closeChat();return;}
            var p:Point=scene.globalToLocal(new Point(e.stageX,e.stageY));
            if(scene.canWalk(p.x,p.y))target=p;
        }
        private function showPanel(name:String):void {
            if(editing)closeChat();modalName=name;historyScroll=0;target=null;joystick.setAvailable(false);scene.move(0,0,0);drawPanel();
        }
        private function closePanel():void {modalName="";modal.removeChildren();modal.graphics.clear();joystick.setAvailable(!editing);}
        private function drawPanel():void {
            modal.removeChildren();modal.graphics.clear();modal.graphics.beginFill(0x08281b,.62);modal.graphics.drawRect(0,0,stage.stageWidth,stage.stageHeight);modal.graphics.endFill();
            var w:Number=Math.min(480,box.safe.width),h:Number=Math.min(stage.stageHeight-40,500);
            var x:Number=(stage.stageWidth-w)/2,y:Number=(stage.stageHeight-h)/2;
            var skin:Sprite=OriginalUI.panelBackground(w,h);skin.x=x;skin.y=y;modal.addChild(skin);
            var title:String=modalName=="inventory"?"התיק · תצוגה מקומית":modalName=="tasks"?"משימות":modalName=="resident"?"היתקליף":String(OriginalUI.TITLES[modalName]);
            label(modal,title,x+12,y+14,w-24,20,0x264421);
            var close:Sprite=OriginalUI.closeButton(closePanel);close.x=x+(w-48)/2;close.y=y+h-48;modal.addChild(close);
            if(modalName=="inventory"){
                var avatar:Sprite=scene.clothingPreview();avatar.x=x+w/2;avatar.y=y+Math.min(230,h-100);avatar.scaleX=avatar.scaleY=1.3;modal.addChild(avatar);
                iconButton(modal,"rotate",x+12,y+h-56,function():void{GameArtwork.pose(avatar,"w_stand");});
                label(modal,"הבגדים המקוריים של דמות הבדיקה",x+12,y+48,w-24,15,0x264421);
            }else if(modalName=="tasks"){
                label(modal,"אין נתוני משימות בהדגמה המקומית",x+20,y+65,w-40,19,0xffffff);
            }else label(modal,modalName=="resident"?"שלום! זו סצנת בדיקה מקומית.":"הכפתור המקורי — החיבור לנתוני המשחק\nאינו פעיל בהדגמה המקומית.",x+20,y+65,w-40,19,0xffffff);
        }
        private function deactivate(e:Event):void {joystick.reset();touches={};pinchDistance=0;target=null;if(editing&&!rendering)closeChat();}
        private function frame(e:Event):void {
            var now:int=getTimer(),dt:Number=Math.min(.05,(now-previous)/1000);previous=now;scene.tick(dt);
            if(!editing&&modalName==""){
                var dx:Number=vx,dy:Number=vy;
                if(target){var a:Number=target.x-scene.player.x,b:Number=target.y-scene.player.y,d:Number=Math.sqrt(a*a+b*b);
                    if(d<6)target=null;else{dx=a/d;dy=b/d;}}
                if(scene.move(dx,dy,dt))walked=true;else if(target)target=null;
            }
            updateCamera(dt);messageClock+=dt;feedClock+=dt;
            if(feedClock>.4){feedClock=0;drawFeed();}
            if(messageClock>12&&!rendering){
                messageClock=0;demoMessage++;
                addMessage(demoMessage%2?"נועה · דוגמה":"אורי · דוגמה",demoMessage%2?"אני ליד העץ, רואים אותי?":"אפשר לפתוח את השיחה גם מרחוק",demoMessage%2?650:280);
            }
        }
        private function testChat():void {
            var scale:Number=scene.scaleX;openChat();input.text="טיוטה בעברית";closeChat();openChat();
            if(input.text!="טיוטה בעברית")throw new Error("draft_not_preserved");
            send();if(!editing||input.text!=""||messages[messages.length-1].text!="טיוטה בעברית")throw new Error("send_keep_open");
            if(scene.scaleX!=scale)throw new Error("keyboard_shrink");
            input.text="המשך";toggleCamera();toggleCamera();if(input.text!="המשך"||scene.scaleX!=scale)throw new Error("camera_draft");
            closeChat();showPanel("inventory");if(modalName!="inventory"||joystick.visible)throw new Error("modal_movement");closePanel();
            changeZoom(100);if(zoom!=1.65)throw new Error("zoom_upper_bound");changeZoom(-10);if(zoom!=.75)throw new Error("zoom_lower_bound");changeZoom(1);
            if(!scene.canWalk(scene.player.x,scene.player.y)||scene.canWalk(-1,0))throw new Error("real_walkmask");
            trace("MOBILE_CHAT_DRAFT_CAMERA_MODAL_AND_REAL_ART_PASS");
        }
        private function testGestures():void {
            viewport.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_BEGIN,true,false,31,false,100,140));
            viewport.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_BEGIN,true,false,32,false,200,140));
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_MOVE,true,false,32,false,250,140));
            if(Math.abs(zoom-1.5)>.001||vx!=0||vy!=0)throw new Error("pinch_cancels_move_and_zooms");
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_END,true,false,31));
            stage.dispatchEvent(new TouchEvent(TouchEvent.TOUCH_END,true,false,32));
            if(touchPoints().length!=0||pinchDistance!=0)throw new Error("pinch_release_cleanup");
            changeZoom(1);suppressClick=false;joystick.travelled=false;
            var npc:DisplayObject=scene.actors.getChildByName("resident");npc.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(modalName!="resident"||target!=null)throw new Error("npc_opens_dialog_without_movement");closePanel();
            trace("MOBILE_PINCH_AND_NPC_INTERACTION_PASS");
        }
        private function testMenu():void {
            var mode:Boolean=overview;
            var mapButton:Sprite=hud.getChildByName("מפה") as Sprite;
            if(!mapButton)throw new Error("original_map_button_missing");
            mapButton.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(modalName!="map"||overview!=mode)throw new Error("map_repurposed_as_zoom");closePanel();
            for each(var id:String in OriginalUI.DOCK){
                var b:Sprite=hud.getChildByName(OriginalUI.TITLES[id]) as Sprite;
                if(!b||b.width<44||b.height<44)throw new Error("original_button_touch_target_"+id);
            }
            trace("MOBILE_ORIGINAL_MENU_ACTIONS_AND_HIT_TARGETS_PASS");
            var camera:Sprite=hud.getChildByName("action-"+(overview?"follow":"overview")) as Sprite;
            camera.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(overview==mode)throw new Error("overview_icon_action");
            cameraButton.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(overview!=mode)throw new Error("follow_icon_action");
            var messagesButton:Sprite=hud.getChildByName("action-messages") as Sprite;
            if(messagesButton.width<44||messagesButton.height<44)throw new Error("message_icon_touch_target");
            var wasVisible:Boolean=history.visible;messagesButton.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            if(history.visible==wasVisible)throw new Error("message_icon_action");
            messagesButton.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
            trace("MOBILE_ICON_CAMERA_AND_MESSAGES_ACTIONS_PASS");
        }
        private function testRotation():void {
            var width:int=stage.stageWidth;openChat();input.text="טיוטה בסיבוב";history.visible=true;history.draw();rotate();
            setTimeout(function():void {
                if(stage.stageWidth==width||input.text!="טיוטה בסיבוב"||!editing||!history.visible||history.y+history.height>box.composer.y){
                    trace("MOBILE_TESTS_FAIL native_rotation_or_draft");NativeApplication.nativeApplication.exit(1);return;
                }
                trace("MOBILE_NATIVE_ROTATION_DRAFT_PASS "+stage.stageWidth+"x"+stage.stageHeight);
                trace("MOBILE_TESTS_PASS");NativeApplication.nativeApplication.exit(0);
            },500);
        }
        private function snapshotIcons():void {
            var pixels:BitmapData=new BitmapData(800,340,false,0x173d32);pixels.draw(new MobileIconLibrary());
            var file:File=File.applicationStorageDirectory.resolvePath("vector-icons.png");
            var stream:FileStream=new FileStream();stream.open(file,FileMode.WRITE);stream.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));stream.close();pixels.dispose();
            trace("MOBILE_VECTOR_RENDER "+file.nativePath);
        }
        private function snapshot(name:String):void {
            var pixels:BitmapData=new BitmapData(stage.stageWidth,stage.stageHeight,false,0x153c31);pixels.draw(this);
            if(editing){var nativePixels:BitmapData=new BitmapData(input.viewPort.width,input.viewPort.height,true,0);input.drawViewPortToBitmapData(nativePixels);pixels.copyPixels(nativePixels,nativePixels.rect,input.viewPort.topLeft,null,null,true);nativePixels.dispose();}
            var file:File=File.applicationStorageDirectory.resolvePath("preview-"+stage.stageWidth+"x"+stage.stageHeight+"-"+name+".png");
            var stream:FileStream=new FileStream();stream.open(file,FileMode.WRITE);stream.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));stream.close();pixels.dispose();trace("MOBILE_RENDER "+file.nativePath);
        }
    }
}
