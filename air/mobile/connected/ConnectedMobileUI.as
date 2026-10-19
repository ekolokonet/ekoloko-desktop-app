package {
    import flash.display.*;
    import org.ekoloko.air.NativeServices;
    import flash.events.*;
    import flash.geom.*;
    import flash.text.*;
    import flash.utils.*;
    import flash.system.Capabilities;
    import flash.ui.Multitouch;
    import flash.ui.MultitouchInputMode;

    /** Presentation/input adapter around live Main; no socket or account API. */
    public final class ConnectedMobileUI extends Sprite {
        private var viewport:Sprite,gameProvider:Function,hostLayout:Function;
        private var main:Object,ui:DisplayObjectContainer,menu:DisplayObjectContainer;
        private var chat:DisplayObjectContainer,field:TextField,sendButton:DisplayObject;
        private var input:StageText;
        private var nativeKeyboard:Boolean=Capabilities.version.indexOf("IOS")==0||Capabilities.version.indexOf("AND")==0;
        private var actions:Sprite=new Sprite(),composer:Sprite=new Sprite();
        private var history:RecentMessages=new RecentMessages();
        private var joystick:TouchJoystick;
        private var saved:Dictionary=new Dictionary(true),seenBubbles:Dictionary=new Dictionary(true);
        private var buttonBounds:Dictionary=new Dictionary(true);
        private var messages:Array=[];
        private var box:Object,view:Object,screenW:Number=844,screenH:Number=390;
        private var active:Boolean=false,editing:Boolean=false,overview:Boolean=false,originalView:Boolean=false;
        private var keyboardHudHidden:Boolean=false,historyBeforeKeyboard:Boolean=false;
        private var inputFocus:MobileInputFocus=new MobileInputFocus(),chatOpenAfter:int=0;
        private var nativeDraft:MobileChatDraft=new MobileChatDraft();
        private var syncingChat:Boolean=false,chatChanges:uint=0,chatSubmits:uint=0,chatCloses:uint=0;
        private var editingKeyboard:Rectangle;
        private var nativeSafe:Rectangle,nativeScreen:Rectangle;
        private var zoom:Number=1,moveX:Number=0,moveY:Number=0,lastMove:int=0,probeAt:int=0;
        private var moving:Boolean=false,room:Object,lastRoom:Object,lastSignature:String="";
        private var touchStartTime:int=0;
        private var dragStart:Point,suppressClick:Boolean=false;
        private var questPanel:MobileQuestPanel,questObject:DisplayObjectContainer,historyBeforeQuest:Boolean=false;
        private var conversationFocus:MobileConversationFocus=new MobileConversationFocus();
        private var conversationSubjects:Object,conversationSafe:Rectangle;
        private var cameraState:Object,lastCameraTime:int=0,cameraSignature:String="",cameraFrom:Object,cameraStarted:int=0;
        private var dock:Object;
        private var chatFieldRect:Rectangle;
        private var chatPresentation:NativeChatPresentation;
        private var chatDelivery:NativeChatDelivery,nativeChatDispatch:Boolean=false;
        private var entry:MobileEntryUI,entryActive:Boolean=false;
        private var drawer:MobileNativeDrawer,drawerObject:DisplayObjectContainer,menuOps:Object;
        private var mapObject:DisplayObject,historyBeforeMap:Boolean;
        private var recycleObject:DisplayObject,historyBeforeRecycle:Boolean;
        private var suspended:Boolean=false,resumeDraft:String="",resumePlayer:Number=0;
        private var frameLayout:NativeFrameLayoutCache=new NativeFrameLayoutCache();
        public function get hasSession():Boolean {return main!=null;}
        public function get sessionConnected():Boolean {
            try{return main && main.SFS && main.SFS.isConnected;}catch(ignored:Error){return false;}
        }
        public function suspend(value:Boolean):void {
            suspended=value;if(value){cancelMove();closeChat();}
        }
        public function retainDraftForRestart():void {
            syncDraft();
            if(main&&main.myPlayer&&field&&"getPlayerId" in main.myPlayer){
                resumePlayer=Number(main.myPlayer.getPlayerId());resumeDraft=field.text;
            }
        }
        private static const DOCK:Array=["userSettingsBut","myHouse","myAnimal","emoticons","myData","quests","buddies","map","cards"];

        public function ConnectedMobileUI(world:Sprite,provider:Function,relayout:Function,mobileMode:Boolean=false) {
            nativeKeyboard=nativeKeyboard||mobileMode;
            viewport=world;gameProvider=provider;hostLayout=relayout;
            mouseEnabled=false;addChild(actions);addChild(history);addChild(composer);
            joystick=new TouchJoystick(function(x:Number,y:Number):void{moveX=x;moveY=y;});addChild(joystick);
            entry=new MobileEntryUI(setScreenTransform);addChild(entry);
            addEventListener(Event.ADDED_TO_STAGE,added);
        }
        private function added(e:Event):void {
            Multitouch.inputMode=MultitouchInputMode.TOUCH_POINT;
            input=new StageText();input.visible=false;input.fontFamily="Arial";input.fontWeight="bold";input.fontSize=18;input.color=0x203C2B;
            input.locale="he-IL";input.textAlign="right";input.returnKeyLabel="done";
            input.addEventListener(KeyboardEvent.KEY_DOWN,inputKey);
            input.addEventListener(Event.CHANGE,syncDraft);
            input.addEventListener(Event.COMPLETE,function(e:Event):void{
                // COMPLETE also fires for viewport changes. Focus only once per
                // explicit open, never in response to keyboard resize/dismissal.
                if(nativeKeyboard&&editing&&inputFocus.complete()){input.visible=true;input.assignFocus();}
            });
            input.addEventListener(SoftKeyboardEvent.SOFT_KEYBOARD_ACTIVATE,keyboardChanged);
            input.addEventListener(SoftKeyboardEvent.SOFT_KEYBOARD_DEACTIVATE,keyboardChanged);
            stage.addEventListener(SoftKeyboardEvent.SOFT_KEYBOARD_ACTIVATE,keyboardChanged);
            stage.addEventListener(SoftKeyboardEvent.SOFT_KEYBOARD_DEACTIVATE,keyboardChanged);
            stage.addEventListener(FocusEvent.FOCUS_IN,focusIn,true);
            stage.addEventListener(Event.ADDED,bubbleAdded,true);
            stage.addEventListener(MouseEvent.MOUSE_DOWN,worldDown,true);
            stage.addEventListener(MouseEvent.MOUSE_UP,worldUp,true);
            stage.addEventListener(MouseEvent.CLICK,worldClick,true,1000);
            stage.addEventListener(TouchEvent.TOUCH_BEGIN,touchDown,true);
            stage.addEventListener(TouchEvent.TOUCH_END,touchUp,true);
            stage.addEventListener(Event.DEACTIVATE,deactivate);
            // Apply presentation after legacy frame scripts and TweenMax finish.
            stage.addEventListener(Event.EXIT_FRAME,frame,false,-2000);
        }
        public function configure(value:Object,w:Number,h:Number):void {
            view=value;screenW=w;screenH=h;x=view.left;y=view.top;scaleX=scaleY=1/view.outerScale;
            lastSignature="";if(active)layout();
        }
        private function remember(o:DisplayObject):void {
            if(o&&!saved[o])saved[o]={matrix:o.transform.matrix.clone(),alpha:o.alpha,width:o.width,height:o.height,bounds:o.getBounds(o).clone(),scroll:o.scrollRect,autoSize:o is TextField?TextField(o).autoSize:null,multiline:o is TextField?TextField(o).multiline:false,wordWrap:o is TextField?TextField(o).wordWrap:false,children:o is DisplayObjectContainer?DisplayObjectContainer(o).mouseChildren:false,mouse:o is InteractiveObject?InteractiveObject(o).mouseEnabled:false};
        }
        private function restore():void {
            clearMap();clearRecycle();
            if(chatPresentation){chatPresentation.dispose();chatPresentation=null;}
            clearDrawer();
            clearQuest();
            for(var key:Object in saved){var o:DisplayObject=key as DisplayObject;if(o){o.transform.matrix=saved[key].matrix;o.alpha=saved[key].alpha;o.scrollRect=saved[key].scroll;if(o is DisplayObjectContainer)DisplayObjectContainer(o).mouseChildren=saved[key].children;if(o is InteractiveObject)InteractiveObject(o).mouseEnabled=saved[key].mouse;if(o is TextField){TextField(o).autoSize=saved[key].autoSize;TextField(o).multiline=saved[key].multiline;TextField(o).wordWrap=saved[key].wordWrap;o.width=saved[key].width;o.height=saved[key].height;}}}
            frameLayout.clear();
            saved=new Dictionary(true);
            buttonBounds=new Dictionary(true);
        }
        public function detachGame():void {
            if(chatDelivery){chatDelivery.dispose();chatDelivery=null;}
            if(field)field.removeEventListener(KeyboardEvent.KEY_UP,chatKeyUp);
            if(ui){ui.removeEventListener(Event.ADDED,presentationChanged,true);ui.removeEventListener(Event.REMOVED,presentationChanged,true);ui.removeEventListener(Event.CHANGE,presentationChanged,true);ui.removeEventListener(MouseEvent.CLICK,presentationChanged,true);}
            frameLayout.clear();
            entry.reset();entryActive=false;
            closeChat();cancelMove();if(field)field.removeEventListener(Event.CHANGE,draftChanged);if(chat)chat.removeEventListener(MouseEvent.CLICK,chatClicked,true);if(ui)ui.removeEventListener(MouseEvent.CLICK,stopUIWorldClick);restore();main=null;ui=null;menu=null;chat=null;field=null;sendButton=null;room=null;lastRoom=null;
            active=false;visible=false;history.visible=false;messages=[];history.update(messages);seenBubbles=new Dictionary(true);
            viewport.scrollRect=new Rectangle(0,0,960,600);lastSignature="";
            cameraState=null;cameraSignature="";conversationFocus.reset();
        }
        private function findClass(root:DisplayObject,name:String,depth:int=0):DisplayObject {
            if(!root||depth>10)return null;
            if(getQualifiedClassName(root)==name)return root;
            if(name=="com.vtweens.shell::Main"&&"uiLayer" in root&&"myPlayer" in root&&"SFS" in root)return root;
            var c:DisplayObjectContainer=root as DisplayObjectContainer;
            if(c)for(var i:int=0;i<c.numChildren;i++){var found:DisplayObject=findClass(c.getChildAt(i),name,depth+1);if(found)return found;}
            return null;
        }
        private function inputField(root:DisplayObjectContainer):TextField {
            for(var i:int=0;i<root.numChildren;i++){
                var o:DisplayObject=root.getChildAt(i);if(o is TextField&&TextField(o).type==TextFieldType.INPUT)return o as TextField;
                if(o is DisplayObjectContainer){var f:TextField=inputField(o as DisplayObjectContainer);if(f)return f;}
            }return null;
        }
        private function named(root:DisplayObjectContainer,name:String):DisplayObject {
            var o:DisplayObject=root.getChildByName(name);if(o)return o;
            for(var i:int=0;i<root.numChildren;i++)if(root.getChildAt(i) is DisplayObjectContainer){o=named(root.getChildAt(i) as DisplayObjectContainer,name);if(o)return o;}
            return null;
        }
        private function attach(found:Object):void {
            main=found;ui=main.uiLayer as DisplayObjectContainer;menu=main.uiLayer._mainMenu as DisplayObjectContainer;
            menuOps=DisplayObject(main).loaderInfo.applicationDomain.getDefinition("com.vtweens.util.menu.MenuDisplayOps");
            chat=findClass(ui,"com.vtweens.components.chat::ChatInput") as DisplayObjectContainer;
            if(!menu||!chat){main=null;return;}
            field=inputField(chat);sendButton=named(chat,"submitBut");
            if(!field||!sendButton){main=null;return;}
            field.addEventListener(Event.CHANGE,draftChanged,false,-1000);
            field.addEventListener(KeyboardEvent.KEY_UP,chatKeyUp,false,10000);
            chatDelivery=new NativeChatDelivery(chat,field,deliveryChanged,deliveryFailed);
            if(resumePlayer>0&&main.myPlayer&&"getPlayerId" in main.myPlayer&&Number(main.myPlayer.getPlayerId())==resumePlayer&&resumeDraft.length)
                NativeChatDelivery.syncInput(field,resumeDraft);
            resumeDraft="";resumePlayer=0;
            nativeDraft.accept(field.text);
            chat.addEventListener(MouseEvent.CLICK,chatClicked,true,1000);
            ui.addEventListener(MouseEvent.CLICK,stopUIWorldClick,false,-1000);
            ui.addEventListener(Event.ADDED,presentationChanged,true);
            ui.addEventListener(Event.REMOVED,presentationChanged,true);
            ui.addEventListener(Event.CHANGE,presentationChanged,true);
            ui.addEventListener(MouseEvent.CLICK,presentationChanged,true);
            active=true;visible=true;lastSignature="";remember(ui);remember(menu);remember(chat);remember(field);
            trace("MOBILE_LIVE_BIND menus=original chat=original history=accepted_bubbles");layout();dispatchEvent(new Event("mobileReady",true));
        }
        private function stopUIWorldClick(e:MouseEvent):void {if(active)e.stopPropagation();}
        private function isShown(o:DisplayObject):Boolean {
            if(!o||!o.stage)return false;
            while(o&&o!=stage){if(!o.visible)return false;o=o.parent;}return true;
        }
        private function frame(e:Event):void {
            try {frameImpl(e);} catch(error:Error) {NativeServices.recordRuntimeFailure(error,"mobile_frame");throw error;}
        }
        private function frameImpl(e:Event):void {
            if(!view||suspended)return;
            var game:Loader=gameProvider();
            if(main&&(!game||!DisplayObject(main).stage)){detachGame();hostLayout();}
            if(!main){
                var wasEntry:Boolean=entryActive;
                entryActive=entry.update(game,screenW,screenH);
                if(entryActive){viewport.scrollRect=null;visible=true;actions.visible=history.visible=composer.visible=false;}
                else if(wasEntry){viewport.scrollRect=new Rectangle(0,0,960,600);visible=false;hostLayout();}
                if(getTimer()<probeAt)return;probeAt=getTimer()+500;
                var found:Object=game?findClass(game,"com.vtweens.shell::Main"):null;
                if(found&&found.uiLayer&&found.myPlayer&&found.room&&found.room.active){entry.reset();entryActive=false;attach(found);}
                return;
            }
            room=main.room;
            var ready:Boolean=room&&main.myPlayer&&room.active&&isShown(ui)&&isShown(room as DisplayObject)&&!(main.house&&main.house.isActive);
            if(!ready||originalView){
                if(active){closeChat();cancelMove();restore();active=false;viewport.scrollRect=new Rectangle(0,0,960,600);hostLayout();}
                visible=originalView;actions.visible=originalView;history.visible=false;composer.visible=false;
                if(originalView)drawActions(true);return;
            }
            if(!active){active=true;visible=true;lastSignature="";remember(ui);remember(menu);remember(chat);remember(field);}
            if(editing&&!chatAllowed())closeChat();
            if(lastRoom!=room){lastRoom=room;cancelMove();lastSignature="";cameraState=null;}
            var keyboard:Rectangle=keyboardBounds();
            var signature:String=screenW+":"+screenH+":"+editing+":"+keyboard.toString();
            for each(var dockId:String in DOCK){var dockButton:DisplayObject=menu.getChildByName(dockId);signature+=":"+(dockButton&&dockButton.visible);}
            if(signature!=lastSignature){lastSignature=signature;layout();}
            updateCamera();refreshPresentation();
            if(moving&&(!canMove()||moveX==0&&moveY==0)){stopWalking();}
            if((moveX||moveY)&&canMove()&&getTimer()-lastMove>=250){
                lastMove=getTimer();moving=ConnectedGameInput.move(main,moveX,moveY)||moving;
            }
            if(editing)updateNativeField();
        }
        private function setScreenTransform(o:DisplayObject,px:Number,py:Number,sx:Number,sy:Number):void {
            if(!o.parent)return;remember(o);
            var a:Point=o.parent.globalToLocal(localToGlobal(new Point(px,py)));
            var b:Point=o.parent.globalToLocal(localToGlobal(new Point(px+sx*1024,py)));
            var c:Point=o.parent.globalToLocal(localToGlobal(new Point(px,py+sy*1024)));
            var next:Matrix=new Matrix((b.x-a.x)/1024,(b.y-a.y)/1024,(c.x-a.x)/1024,(c.y-a.y)/1024,a.x,a.y);
            var old:Matrix=o.transform.matrix;
            if(Math.abs(old.a-next.a)+Math.abs(old.b-next.b)+Math.abs(old.c-next.c)+Math.abs(old.d-next.d)+Math.abs(old.tx-next.tx)+Math.abs(old.ty-next.ty)>.00001)o.transform.matrix=next;
        }
        private function place(o:DisplayObject,r:Rectangle,art:DisplayObject=null,stable:Boolean=false,maxScale:Number=1.4,curtain:Boolean=false):void {
            if(!o||!o.parent)return;
            var bounds:Rectangle=stable&&buttonBounds[o]?buttonBounds[o]:art?art.getBounds(o):o.getBounds(o);
            if(bounds.width<=0||bounds.height<=0)return;
            if(stable&&!buttonBounds[o])buttonBounds[o]=bounds.clone();
            var s:Number=Math.min(r.width/bounds.width,r.height/bounds.height,maxScale);
            var top:Number=curtain?menuOffset(o,bounds.height*s):(r.height-bounds.height*s)/2;
            setScreenTransform(o,r.x+(r.width-bounds.width*s)/2-bounds.x*s,r.y+top-bounds.y*s,s,s);
        }
        private function keyboardBounds():Rectangle {
            if(!editing||!stage)return new Rectangle();
            // Same native-pixel/display-point ratio used by the host viewport.
            var pixelScale:Number=Capabilities.version.indexOf("IOS")==0?stage.fullScreenWidth/screenW:0;
            var current:Rectangle=MobileConversationCamera.keyboardBounds(this,stage.softKeyboardRect,screenW,screenH,pixelScale);
            // A Send tap may briefly blur StageText. Keep its button in place
            // through that pointer gesture instead of deleting/rebuilding it.
            if(!current.isEmpty())editingKeyboard=current.clone();
            if(current.isEmpty()&&editingKeyboard&&editingKeyboard.right<=screenW&&editingKeyboard.bottom<=screenH)return editingKeyboard.clone();
            return current;
        }
        private function layout():void {
            if(!active||!view)return;
            var portrait:Boolean=screenH>screenW;
            var keyboard:Rectangle=keyboardBounds();
            // ADL has a hardware keyboard; only real runtime keyboard bounds reduce the view.
            var insets:Object={left:portrait?12:24,right:portrait?12:24,top:8,bottom:12};
            if(nativeKeyboard){
                try{
                    nativeScreen=Screen.mainScreen.bounds;nativeSafe=Screen.mainScreen.safeArea;
                    if(Capabilities.version.indexOf("IOS")==0&&nativeScreen.equals(nativeSafe)&&Math.max(screenW,screenH)/Math.min(screenW,screenH)>2)
                        insets=portrait?{left:12,right:12,top:64,bottom:34}:{left:64,right:64,top:8,bottom:21};
                    insets=MobileLayout.safeInsets(screenW,screenH,nativeScreen,nativeSafe,insets);
                }catch(ignored:Error){}
            }
            box=MobileLayout.calculate(screenW,screenH,insets,keyboard,editing);
            var left:Array=[],right:Array=[];
            for(var i:int=0;i<DOCK.length;i++){var item:DisplayObject=menu.getChildByName(DOCK[i]);if(DOCK[i]!="cards"&&item&&item.visible)(i<4?left:right).push(DOCK[i]);}
            dock=ConnectedDockLayout.calculate(box.safe,left,right);box.chat=dock.chat;box.toolbar=dock.toolbar;
            viewport.scrollRect=null;actions.visible=true;composer.visible=true;
            drawActions();history.fit(new Rectangle(box.safe.x,72,box.safe.width,Math.max(110,(editing?box.composer.y:box.toolbar.y)-76)));
            frameLayout.invalidate();updateCamera();refreshPresentation();
            updateKeyboardHud();
        }
        private function updateKeyboardHud():void {
            var hide:Boolean=editing&&box&&box.compactComposer;
            if(hide&&!keyboardHudHidden)historyBeforeKeyboard=history.visible;
            if(!hide&&keyboardHudHidden)history.visible=historyBeforeKeyboard;
            keyboardHudHidden=hide;
            if(hide){actions.visible=false;history.visible=false;}
        }
        private function presentationChanged(e:Event):void {frameLayout.invalidate();}
        private function presentationObjects():Array {
            var result:Array=[menu,chat,field,sendButton,sendButton?sendButton.parent:null,field?field.parent:null];
            for(var i:int=0;i<ui.numChildren;i++)result.push(ui.getChildAt(i));
            for(i=0;i<menu.numChildren;i++){
                var child:DisplayObject=menu.getChildAt(i);result.push(child);
                var container:DisplayObjectContainer=child as DisplayObjectContainer;
                if(container)result.push(container.getChildByName("popup"));
            }
            if(chat)for(i=0;i<chat.numChildren;i++)result.push(chat.getChildAt(i));
            return result;
        }
        private function animatedPresentation():Boolean {
            // Keep all authored modal/shutter/timeline paths on every EXIT_FRAME.
            // RequestsPanel has a permanently present ScrollPane: its native child
            // animations run independently; additions/changes invalidate placement.
            for(var i:int=0;i<ui.numChildren;i++){
                var o:DisplayObjectContainer=ui.getChildAt(i) as DisplayObjectContainer;
                if(o&&o!=menu&&o!=chat&&o.visible&&o.numChildren>0&&getQualifiedClassName(o)!="com.vtweens.components.interaction::RequestsPanel")return true;
            }
            for each(var id:String in ["buddies","emoticons"]){
                var c:DisplayObjectContainer=menu.getChildByName(id) as DisplayObjectContainer;
                var popup:DisplayObject=c?c.getChildByName("popup"):null;
                if(popup&&popup.visible)return true;
            }
            return false;
        }
        private function refreshPresentation():void {
            if(!active||!ui||!menu||!box)return;
            if(!frameLayout.needs(presentationObjects(),animatedPresentation()))return;
            reflowMenus();layoutSecurityPopup();
            updateKeyboardHud();
            // Capture after our transforms so the next stable frame is a cache hit.
            frameLayout.commit(presentationObjects());
        }
        private function updateCamera():void {
            if(!room||!main.myPlayer||!box)return;
            var p:DisplayObject=main.myPlayer as DisplayObject;
            // The original HTML embed clips room artwork at 960x600. Keep that
            // boundary on the world layer, while the counter-scaled UI remains free.
            var world:DisplayObject=DisplayObject(room).parent;
            if(world){remember(world);if(!world.scrollRect)world.scrollRect=new Rectangle(0,0,960,600);}
            // Track the world anchor, not the avatar's animated/scaled artwork.
            var focus:Point=DisplayObject(main).globalToLocal(p.parent.localToGlobal(new Point(p.x,p.y-70)));
            // Keep world coverage to the keyboard edge; conversation framing also avoids the composer.
            var available:Rectangle=box.viewport.clone();
            var s:Number=Math.max(Math.max(.9,screenW/960,screenH/600)*zoom,available.width/960,available.height/600);
            var composing:Boolean=editing&&available.height<screenH-1;
            var key:String=available.width+":"+available.height+":"+s+":"+overview+":"+composing;
            var now:int=getTimer(),snap:Boolean=!cameraState;
            var camera:Object;
            if(snap){cameraState={scale:viewport.scaleX*view.outerScale,x:(viewport.x-view.left)*view.outerScale,y:(viewport.y-view.top)*view.outerScale};}
            if(snap||key!=cameraSignature){cameraFrom={scale:cameraState.scale,x:cameraState.x,y:cameraState.y};cameraStarted=now;}
            if(composing){
                cameraFrom=null;
                var subjects:Object=conversationFocus.sample(p,DisplayObject(main),now);
                var safe:Rectangle=new Rectangle(box.safe.x+8,Math.max(10,box.safe.y),box.safe.width-16,Math.max(32,box.composer.y-Math.max(10,box.safe.y)-8));
                conversationSubjects=subjects;conversationSafe=safe;
                var conversation:Object=MobileConversationCamera.target(available,safe,s,subjects.own,subjects.neighbors);
                camera=MobileConversationCamera.approach(cameraState,conversation,now-lastCameraTime);
            }
            else if(cameraFrom){
                var target:Object=MobileCamera.calculate(available,s,focus.x,focus.y,overview);
                var progress:Number=Math.min(1,(now-cameraStarted)/320),ease:Number=progress*progress*(3-2*progress);
                camera={scale:cameraFrom.scale+(target.scale-cameraFrom.scale)*ease,x:cameraFrom.x+(target.x-cameraFrom.x)*ease,y:cameraFrom.y+(target.y-cameraFrom.y)*ease};
                if(progress==1)cameraFrom=null;
            }
            else if(overview)camera=MobileCamera.calculate(available,s,focus.x,focus.y,true);
            else {
                camera=MobileCamera.smoothFollow(available,s,focus.x,focus.y,cameraState,now-lastCameraTime);
            }
            camera=MobileConversationCamera.constrain(available,camera);
            cameraState=camera;cameraSignature=key;lastCameraTime=now;
            // Snap translation to device pixels to avoid subpixel shimmer in room art.
            var pixelScale:Number=stage.contentsScaleFactor;
            camera={scale:camera.scale,x:Math.round(camera.x*pixelScale)/pixelScale,y:Math.round(camera.y*pixelScale)/pixelScale};
            // Rounding at a room edge must not reveal even a fractional strip outside it.
            camera=MobileConversationCamera.constrain(available,camera);
            viewport.scaleX=viewport.scaleY=camera.scale/view.outerScale;
            viewport.x=view.left+camera.x/view.outerScale;viewport.y=view.top+camera.y/view.outerScale;
            // Counter-transform only the live UI. World mouse coordinates stay in Main.
            setScreenTransform(ui,0,0,1,1);setScreenTransform(menu,0,0,1,1);
        }
        private function buttonArt(o:DisplayObject,id:String):DisplayObject {
            var c:DisplayObjectContainer=o as DisplayObjectContainer;if(!c)return o;
            // The house clip also contains a hidden, very wide edit-mode label.
            if(id=="myHouse"&&c.numChildren)return c.getChildAt(0);
            return c.getChildByName(id=="buddies"||id=="emoticons"?"but":id=="map"?"regular":"up")||o;
        }
        private function reflowMenus():void {
            if(!active||!box||!menu)return;
            menu.alpha=editing?0:saved[menu].alpha;menu.mouseChildren=editing?false:saved[menu].children;menu.mouseEnabled=editing?false:saved[menu].mouse;
            var currentRecycle:DisplayObject;
            for(var ri:int=0;ri<ui.numChildren;ri++){
                var reward:DisplayObject=ui.getChildAt(ri);
                if(reward.visible&&getQualifiedClassName(reward)=="DaysPalyedRewardPane"){currentRecycle=reward;break;}
            }
            if(currentRecycle!=recycleObject){clearRecycle();if(currentRecycle){recycleObject=currentRecycle;historyBeforeRecycle=history.visible;remember(recycleObject);if(editing)closeChat();}}
            if(recycleObject){
                clearMap();clearDrawer();clearQuest();cancelMove();
                menu.alpha=0;menu.mouseChildren=menu.mouseEnabled=false;
                chat.alpha=0;chat.mouseEnabled=chat.mouseChildren=false;
                actions.visible=history.visible=composer.visible=false;
                NativeRecycleLayout.fit(recycleObject,box.safe,menuOffset(recycleObject,1),setScreenTransform);return;
            }
            var currentMap:DisplayObject;
            for(var m:int=0;m<ui.numChildren;m++){
                var mapCandidate:DisplayObject=ui.getChildAt(m);
                if(mapCandidate.visible&&getQualifiedClassName(mapCandidate)=="MapPanelMC"){currentMap=mapCandidate;break;}
            }
            if(currentMap!=mapObject){clearMap();if(currentMap){mapObject=currentMap;historyBeforeMap=history.visible;remember(mapObject);if(editing)closeChat();}}
            if(mapObject){
                clearDrawer();clearQuest();cancelMove();
                menu.alpha=0;menu.mouseChildren=menu.mouseEnabled=false;
                chat.alpha=0;chat.mouseEnabled=chat.mouseChildren=false;
                actions.visible=history.visible=composer.visible=false;
                NativeMapLayout.fit(mapObject,box.safe,menuOffset(mapObject,1),setScreenTransform);return;
            }
            var currentQuest:DisplayObjectContainer;
            for(var q:int=0;q<ui.numChildren;q++){
                var candidate:DisplayObject=ui.getChildAt(q);
                if(candidate.visible&&"groupSlotsContainer" in candidate&&"questSubgroupData" in candidate){currentQuest=candidate as DisplayObjectContainer;break;}
            }
            if(currentQuest!=questObject){clearQuest();if(currentQuest){questObject=currentQuest;remember(questObject);questPanel=new MobileQuestPanel(questObject);historyBeforeQuest=history.visible;}}
            if(questPanel){
                clearDrawer();
                if(editing)closeChat();cancelMove();menu.alpha=0;menu.mouseChildren=menu.mouseEnabled=false;remember(chat);chat.alpha=0;
                actions.visible=history.visible=composer.visible=false;
                questPanel.refresh(box.safe.width,box.safe.height);setScreenTransform(questObject,box.safe.x,menuOffset(questObject,box.safe.height),1,1);return;
            }
            var currentDrawer:DisplayObjectContainer;
            for(q=0;q<ui.numChildren;q++){
                candidate=ui.getChildAt(q);
                if(candidate.visible&&(candidate==Object(ui).myPlayerPanel||candidate==Object(ui).otherUserData||getQualifiedClassName(candidate)=="MyAnimalPanel")){currentDrawer=candidate as DisplayObjectContainer;break;}
            }
            if(currentDrawer!=drawerObject){clearDrawer();if(currentDrawer){drawerObject=currentDrawer;remember(drawerObject);drawer=new MobileNativeDrawer(drawerObject,setScreenTransform);addChild(drawer);if(editing)closeChat();}}
            if(drawer){
                cancelMove();menu.alpha=0;menu.mouseChildren=menu.mouseEnabled=false;
                chat.alpha=editing?1:0;chat.mouseEnabled=chat.mouseChildren=editing;actions.visible=history.visible=false;composer.visible=editing;
                if(editing)layoutChat();
                drawer.refresh(screenW,screenH,editing?box.composer.y-4:screenH,menuOffset(drawerObject,1));return;
            }
            for(var i:int=0;i<DOCK.length;i++){
                var id:String=DOCK[i],o:DisplayObject=menu.getChildByName(id);if(!o)continue;
                if(id=="cards"){remember(o);o.alpha=0;if(o is InteractiveObject)InteractiveObject(o).mouseEnabled=false;if(o is DisplayObjectContainer)DisplayObjectContainer(o).mouseChildren=false;continue;}
                var slot:Rectangle=dock.slots[id];if(slot)place(o,slot,buttonArt(o,id),true,2.4);
                if((id=="buddies"||id=="emoticons")&&o is DisplayObjectContainer){
                    var popup:DisplayObject=DisplayObjectContainer(o).getChildByName("popup");
                    if(popup&&popup.visible)place(popup,new Rectangle(box.safe.x,72,box.safe.width,Math.max(100,box.toolbar.y-76)));
                }
            }
            // Sound is a primary control: keep the original stateful button in a
            // fixed slot instead of burying it in the paged role/event actions.
            var mute:DisplayObject=menu.getChildByName("muteBut");
            if(mute)place(mute,new Rectangle(box.safe.x+54,74,48,48),buttonArt(mute,"muteBut"),true,2.4);
            for each(id in ["help","paperBut","pioStore","community","helper","rangerMessagesBut","donationCampaign","credits","codeGiftButton","timeLimitClock","modEventBlock","logout"]){
                o=menu.getChildByName(id);if(!o)continue;remember(o);
                if(id=="pioStore")place(o,new Rectangle(box.safe.right-48,76,48,48),buttonArt(o,id),true,2.4);
                else {o.alpha=0;if(o is InteractiveObject)InteractiveObject(o).mouseEnabled=false;if(o is DisplayObjectContainer)DisplayObjectContainer(o).mouseChildren=false;}
            }
            if(chatAllowed())layoutChat();
            var noChat:DisplayObject=menu.getChildByName("noChat");
            if(noChat&&noChat.visible)place(noChat,box.chat);
            // Existing popup instances and listeners survive; only their display transforms change.
            for(i=0;i<ui.numChildren;i++){
                o=ui.getChildAt(i);if(o==menu||o==chat||!o.visible)continue;
                var b:Rectangle=o.getBounds(o);
                if(b.width>160&&b.height>90&&(!(o is InteractiveObject)||InteractiveObject(o).mouseEnabled)){
                    var area:Rectangle=new Rectangle(box.safe.x,0,box.safe.width,Math.max(100,(editing?box.composer.y:box.toolbar.y)-6));
                    place(o,area,null,false,1.4,true);
                }
            }
        }
        private function clearQuest():void {
            if(!questPanel)return;questPanel.dispose();questPanel=null;questObject=null;
            if(menu&&saved[menu])menu.alpha=saved[menu].alpha;if(chat&&saved[chat])chat.alpha=saved[chat].alpha;
            actions.visible=composer.visible=true;history.visible=historyBeforeQuest;
        }
        private function clearRecycle():void {
            if(!recycleObject)return;recycleObject=null;
            if(chat&&saved[chat]){chat.alpha=saved[chat].alpha;chat.mouseEnabled=saved[chat].mouse;chat.mouseChildren=saved[chat].children;}
            if(actions)actions.visible=true;if(composer)composer.visible=true;if(history)history.visible=historyBeforeRecycle;
        }
        private function clearMap():void {
            if(!mapObject)return;mapObject=null;
            if(chat&&saved[chat]){chat.alpha=saved[chat].alpha;chat.mouseEnabled=saved[chat].mouse;chat.mouseChildren=saved[chat].children;}
            if(actions)actions.visible=true;if(composer)composer.visible=true;if(history)history.visible=historyBeforeMap;
        }
        private function layoutSecurityPopup():void {
            if(!active||!ui||!box)return;
            // This dialog is a sibling of the profile, not part of its drawer.
            // It must still be fitted after the drawer's early return above.
            for(var i:int=0;i<ui.numChildren;i++){
                var popup:DisplayObjectContainer=ui.getChildAt(i) as DisplayObjectContainer;
                if(!popup||getQualifiedClassName(popup)!="com.vtweens.dataobjects.security.code::SecurityCodePopup"||!popup.visible||popup.numChildren==0)continue;
                remember(popup);
                NativeSecurityPopupLayout.fit(popup,new Rectangle(box.safe.x+8,box.safe.y+8,box.safe.width-16,box.safe.height-16),setScreenTransform);
            }
        }
        private function menuOffset(o:DisplayObject,height:Number):Number {return menuOps&&"mobileMenuOffset" in menuOps?Math.min(0,Number(menuOps.mobileMenuOffset(o)))*height:0;}
        private function clearDrawer():void {
            if(!drawer)return;drawer.dispose();drawer=null;drawerObject=null;
            if(chat&&saved[chat]){chat.alpha=saved[chat].alpha;chat.mouseEnabled=saved[chat].mouse;chat.mouseChildren=saved[chat].children;}
            actions.visible=composer.visible=true;
        }
        private function layoutChat():void {
            var r:Rectangle=(editing?box.composer:box.chat).clone();if(editing){r.x+=50;r.width-=50;}
            setScreenTransform(chat,r.x,r.y,1,1);
            var textBox:DisplayObjectContainer=sendButton.parent;
            place(sendButton,new Rectangle(r.right-41,r.y+(r.height-36)/2,36,36),null,true,2.4);
            if(!chatPresentation)chatPresentation=new NativeChatPresentation(chat,field,textBox.getChildAt(0),this,setScreenTransform,nativeKeyboard);
            chatFieldRect=chatPresentation.refresh(r,r.right-41);
            field.alpha=nativeKeyboard?0:1;
            if(nativeKeyboard)chatPresentation.showDraft(nativeDraft.text,editing);
            if(nativeKeyboard)field.mouseEnabled=false;
            var instructions:DisplayObject=chat.getChildByName("instructionsText");
            if(instructions is TextField){remember(instructions);setScreenTransform(instructions,chatFieldRect.x,chatFieldRect.y,1,1);NativeChatGeometry.constrain(TextField(instructions),chatFieldRect);}
            if(editing)updateNativeField();
        }
        private function addAction(id:String,px:Number,py:Number,fn:Function):void {var b:Sprite=OriginalUI.actionButton(id,fn);b.x=px;b.y=py;actions.addChild(b);}
        private function drawActions(fallback:Boolean=false):void {
            actions.removeChildren();composer.removeChildren();
            if(fallback){addAction("follow",screenW-62,12,function():void{originalView=false;lastSignature="";});return;}
            addAction(overview?"follow":"overview",box.safe.right-48,16,function():void{overview=!overview;drawActions();});
            addAction("messages",box.safe.right-102,16,function():void{history.toggle();});
            addAction("rotate",box.safe.x,16,rotate);
            addAction("zoomIn",box.safe.x+54,16,function():void{zoom=Math.min(1.65,zoom+.15);overview=false;});
            addAction("zoomOut",box.safe.x+108,16,function():void{zoom=Math.max(.75,zoom-.15);overview=false;});
            // Existing desktop menus remain available as a complete reference layout.
            var reset:Sprite=OriginalUI.actionButton("follow",function():void{originalView=true;});reset.x=box.safe.x;reset.y=74;actions.addChild(reset);
            reset.accessibilityProperties.name="התצוגה המקורית של המשחק";
            if(editing){
                var close:Sprite=OriginalUI.actionButton("hideKeyboard",closeChat);close.x=box.composer.x;
                close.y=box.composer.bottom-48;composer.addChild(close);
                if(box.compactComposer){
                    // Keep a 44pt send target even though its visible row is thinner.
                    var sendHit:Sprite=new Sprite();sendHit.name="compactSendTarget";sendHit.buttonMode=true;
                    sendHit.graphics.beginFill(0,0);sendHit.graphics.drawRect(0,0,44,44);sendHit.graphics.endFill();
                    sendHit.x=box.composer.right-44;sendHit.y=box.composer.bottom-44;
                    sendHit.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void{e.stopPropagation();submitChat();});composer.addChild(sendHit);
                }
            }
        }
        private function rotate():void {
            closeChat();
            if(nativeKeyboard){stage.setOrientation(screenW>screenH?"default":"rotatedRight");return;}
            var w:Number=stage.nativeWindow.width,h:Number=stage.nativeWindow.height;stage.nativeWindow.width=h;stage.nativeWindow.height=w;hostLayout();
        }
        private function chatAllowed():Boolean {return chat&&isShown(chat)&&chat.mouseEnabled&&chat.mouseChildren&&field&&field.type==TextFieldType.INPUT;}
        private function chatClicked(e:MouseEvent):void {
            if(!active||!chatAllowed())return;
            if(e.target==sendButton||(sendButton is DisplayObjectContainer&&DisplayObjectContainer(sendButton).contains(e.target as DisplayObject))){e.stopImmediatePropagation();submitChat();return;}
            e.stopImmediatePropagation();openChat();
        }
        private function focusIn(e:FocusEvent):void {
            if(e.target!=field||!active||!chatAllowed())return;
            if(!editing){if(nativeKeyboard)stage.focus=null;openChat();return;}
            // Legacy hideInstructions and Flash pointer focus must never create
            // a second native editor behind StageText.
            if(nativeKeyboard){stage.focus=null;input.assignFocus();}
        }
        private function openChat():void {
            if(editing||getTimer()<chatOpenAfter||!chatAllowed())return;cancelMove();editing=true;editingKeyboard=null;inputFocus.begin(input.stage==stage);conversationFocus.reset();conversationSubjects=null;conversationSafe=null;
            if(nativeKeyboard){
                var hint:DisplayObject=chat.getChildByName("instructionsText");
                if(hint)hint.visible=false;
                stage.focus=null;
            }else if("hideInstructions" in chat)Object(chat).hideInstructions();
            input.text=nativeDraft.text;mirrorDraft();input.maxChars=field.maxChars>0?Math.min(field.maxChars,39):39;
            input.restrict=field.restrict;
            if(nativeKeyboard){if(input.stage!=stage)input.stage=stage;input.visible=true;layout();if(inputFocus.commit())input.assignFocus();}
            else {layout();field.alpha=1;stage.focus=field;field.setSelection(field.text.length,field.text.length);}
        }
        private function mirrorDraft():void {
            if(!field)return;
            syncingChat=true;
            try{NativeChatDelivery.syncInput(field,nativeDraft.text);}finally{syncingChat=false;}
            if(chatPresentation)chatPresentation.showDraft(nativeDraft.text,editing);
        }
        private function syncDraft(e:Event=null):void {
            if(!editing||!nativeKeyboard||!field||syncingChat)return;
            // Only native CHANGE owns edits. A stale StageText snapshot at blur,
            // delivery or close must not replace text entered into the old field.
            if(e){nativeDraft.readNative(input.text,true);chatChanges++;}
            mirrorDraft();
        }
        private function draftChanged(e:Event):void {
            if(syncingChat||!field)return;
            nativeDraft.accept(field.text);chatChanges++;
            if(chatPresentation)chatPresentation.showDraft(nativeDraft.text,editing);
            if(editing&&nativeKeyboard&&input.text!=nativeDraft.text){
                syncingChat=true;try{input.text=nativeDraft.text;}finally{syncingChat=false;}
            }
            if(editing)dispatchEvent(new Event("mobileInputChanged",true));
        }
        private function submitChat():void {
            if(!chatAllowed()||!chatDelivery)return;chatSubmits++;syncDraft();
            // The original ChatInput handles validation/cooldown and dispatches its real ChatEvent.
            chatDelivery.submit(function():void{nativeChatDispatch=true;try{field.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP,true,false,13,13));}finally{nativeChatDispatch=false;}});
            if(editing){if(nativeKeyboard)input.assignFocus();else stage.focus=field;}
            NativeServices.report({stage:"window",reasonCode:"chat_submit"});
        }
        private function chatKeyUp(e:KeyboardEvent):void{if(active&&!originalView&&!nativeChatDispatch&&e.keyCode==13){e.stopImmediatePropagation();submitChat();}}
        private function deliveryChanged():void{
            nativeDraft.accept(field.text);
            if(chatPresentation)chatPresentation.showDraft(nativeDraft.text,editing);
            if(nativeKeyboard&&input.text!=nativeDraft.text){syncingChat=true;try{input.text=nativeDraft.text;}finally{syncingChat=false;}}
            if(sendButton)sendButton.alpha=chatDelivery&&chatDelivery.pending ? 0.55 : 1;
        }
        private function deliveryFailed():void{
            if(active&&main)main.popup("לא התקבל אישור שההודעה הופיעה בצ׳אט. הטקסט לא נמחק; אפשר לנסות שוב.",0,0,16);
        }
        private function inputKey(e:KeyboardEvent):void {if(e.keyCode==13){e.preventDefault();e.stopImmediatePropagation();submitChat();}else if(e.keyCode==27){e.preventDefault();closeChat();}}
        private function closeChat():void {
            if(!editing)return;syncDraft();chatCloses++;editing=false;editingKeyboard=null;inputFocus.close();chatOpenAfter=getTimer()+450;
            conversationFocus.reset();input.visible=false;if(field)field.alpha=1;stage.focus=null;
            if(field){mirrorDraft();field.scrollH=0;}
            lastSignature="";if(active&&main)layout();
            NativeServices.report({stage:"window",reasonCode:"chat_close"});
        }
        private function updateNativeField():void {
            if(!nativeKeyboard||!editing||!field||!box)return;
            // Convert physical adapter points back to stage coordinates. Font
            // size remains in physical pixels, independent of SHOW_ALL scale.
            var r:Rectangle=chatFieldRect?NativeChatGeometry.stageBounds(this,chatFieldRect):null;if(!r||r.isEmpty()){input.visible=false;return;}
            if(!input.viewPort||!input.viewPort.equals(r))input.viewPort=r;
            input.visible=true;
        }
        public function drawInputReview(pixels:BitmapData):void {
            if(!editing||!input||!input.visible||!input.stage)return;
            var r:Rectangle=input.viewPort,nativePixels:BitmapData=new BitmapData(r.width,r.height,true,0);
            try{input.drawViewPortToBitmapData(nativePixels);pixels.copyPixels(nativePixels,new Rectangle(0,0,chatFieldRect.width,chatFieldRect.height),chatFieldRect.topLeft,null,null,true);}catch(error:Error){trace("MOBILE_INPUT_CAPTURE_NOT_READY code="+error.errorID);}finally{nativePixels.dispose();}
        }
        public function get cameraDiagnostics():Object {
            var result:Object={editing:editing,keyboard:rectState(keyboardBounds()),keyboardStage:rectState(stage?stage.softKeyboardRect:null),keyboardCoordinates:Capabilities.version.indexOf("IOS")==0?"nativePixels":"stage",
                dismissKeyboardVisible:editing&&composer.visible&&composer.getChildByName("action-hideKeyboard")!=null,
                gameControlsVisible:actions.visible,compactComposer:box?box.compactComposer:false,composer:box?rectState(box.composer):null,
                nativeSafeArea:rectState(nativeSafe),nativeScreen:rectState(nativeScreen),
                chatInputRevision:7,chatChanges:chatChanges,chatSubmits:chatSubmits,chatCloses:chatCloses,legacyFieldFocused:stage&&stage.focus==field,
                draftCharacters:nativeDraft.text.length,fieldCharacters:field?field.text.replace(/[\u200e\u200f]/g,"").length:0,
                draftPreviewVisible:nativeKeyboard&&!editing&&chatPresentation!=null,fieldVisible:field?field.visible&&field.alpha>0:false,awaitingOwnBubble:chatDelivery?chatDelivery.pending:false};
            if(cameraState&&box){
                var roomBounds:Rectangle=new Rectangle(cameraState.x,cameraState.y,960*cameraState.scale,600*cameraState.scale);
                result.room=rectState(roomBounds);result.viewport=rectState(box.viewport);result.roomCoversViewport=roomBounds.containsRect(box.viewport);
            }
            if(editing&&conversationSubjects&&cameraState&&conversationSafe){
                var own:Rectangle=conversationSubjects.own;
                var projected:Rectangle=new Rectangle(cameraState.x+own.x*cameraState.scale,cameraState.y+own.y*cameraState.scale,own.width*cameraState.scale,own.height*cameraState.scale);
                result.subject=rectState(projected);result.safe=rectState(conversationSafe);result.ownerFullyVisible=conversationSafe.containsRect(projected);result.scale=cameraState.scale;
            }
            return result;
        }
        private static function rectState(rect:Rectangle):Object {return rect?{x:rect.x,y:rect.y,width:rect.width,height:rect.height}:null;}
        private function keyboardChanged(e:Event):void {
            // Native blur also occurs when tapping Send. It is not a request to
            // end composition: only explicit dismiss/world taps close the editor.
            // The frame's geometry signature handles real changes. Rebuilding
            // controls here can destroy a Send target between touch-down/up.
            NativeServices.report({stage:"window",reasonCode:"keyboard_camera_changed"});
        }
        private function canMove():Boolean {return active&&!editing&&main&&room&&room.active&&!main.isMenuOpened()&&!main.isIninWorldGame()&&main.hasEventListener(MouseEvent.CLICK);}
        private function worldTarget(o:DisplayObject):Boolean {return active&&room&&o&&DisplayObjectContainer(room).contains(o)&&!ui.contains(o);}
        private function worldDown(e:MouseEvent):void {
            if(editing&&worldTarget(e.target as DisplayObject)){e.preventDefault();e.stopImmediatePropagation();suppressClick=true;closeChat();return;}
            if(getTimer()-touchStartTime<600||!canMove()||!worldTarget(e.target as DisplayObject))return;
            dragStart=new Point(e.stageX,e.stageY);joystick.beginAt(e.stageX,e.stageY);suppressClick=false;
        }
        private function worldUp(e:MouseEvent):void {if(dragStart){suppressClick=joystick.travelled;dragStart=null;cancelMove();}}
        private function worldClick(e:MouseEvent):void {if(suppressClick&&worldTarget(e.target as DisplayObject)){e.stopImmediatePropagation();suppressClick=false;}}
        private function touchDown(e:TouchEvent):void {touchStartTime=getTimer();
            if(editing&&worldTarget(e.target as DisplayObject)){e.preventDefault();e.stopImmediatePropagation();suppressClick=true;closeChat();return;}
            if(canMove()&&worldTarget(e.target as DisplayObject)){dragStart=new Point(e.stageX,e.stageY);joystick.beginAt(e.stageX,e.stageY,e.touchPointID);}}
        private function touchUp(e:TouchEvent):void {if(dragStart){suppressClick=joystick.travelled;dragStart=null;cancelMove();}}
        private function stopWalking():void {if(moving&&main&&main.myPlayer){main.myPlayer.stopWalking();main.stopMyPlayer();}moving=false;}
        private function cancelMove():void {joystick.reset();stopWalking();moveX=moveY=0;}
        private function deactivate(e:Event):void {cancelMove();closeChat();}
        private function bubbleAdded(e:Event):void {
            if(!main||getQualifiedClassName(e.target)!="com.vtweens.components.chat::ChatBaloon")return;
            var bubble:DisplayObjectContainer=e.target as DisplayObjectContainer;
            var player:Object=bubble.parent;
            if(!player||!("getPlayerName" in player))return;
            var text:String="";for(var i:int=0;i<bubble.numChildren;i++)if(bubble.getChildAt(i) is TextField)text=TextField(bubble.getChildAt(i)).text;
            text=text.replace(/[\r\n]+/g," ").replace(/^\s+|\s+$/g,"");if(!text)return;
            // This event occurs after ChatBaloon.setMessage accepts and formats the message.
            var own:Boolean=player==main.myPlayer;
            if(!own&&main.myPlayer&&"getPlayerId" in player&&"getPlayerId" in main.myPlayer){var id:Number=Number(player.getPlayerId());own=id>0&&id==Number(main.myPlayer.getPlayerId());}
            if(own&&chatDelivery){syncDraft();chatDelivery.confirmBubble(text);}
            messages.push({name:String(player.getPlayerName()),text:text,own:own});if(messages.length>200)messages.shift();history.update(messages);
        }
    }
}
