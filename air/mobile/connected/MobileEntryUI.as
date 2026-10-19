package {
 import flash.display.*;import flash.events.*;import flash.geom.*;import flash.text.*;import flash.utils.Dictionary;
 /** Presentation-only adapter for native WebsiteMain and ServerSelector. */
 public final class MobileEntryUI extends Sprite {
  private var transformObject:Function,root:DisplayObjectContainer,kind:String="",states:Dictionary=new Dictionary(true);
  private var form:DisplayObjectContainer,screenW:Number,screenH:Number,scrollY:Number=0,maxScroll:Number=0;
  // Visible authored panel, excluding off-canvas animation/mask geometry.
  private static const LOGIN_PANEL:Rectangle=new Rectangle(320,80,500,365);
  private var up:Sprite,down:Sprite,drag:Point,last:Point,dragged:Boolean=false;
  private var selectorPage:DisplayObject;
  private var resetting:Boolean=false;
  private var loginInput:MobileLoginInput;
  private var entryActions:MobileEntryActions=new MobileEntryActions();
  private var actionLeaf:DisplayObject,actionW:Number=-1,actionH:Number=-1,actionFrame:int=-1;
  private var scrollControls:Sprite=new Sprite(),revealMask:Shape=new Shape();
  public function MobileEntryUI(position:Function){
   transformObject=position;mouseEnabled=false;
   addChild(scrollControls);addChild(revealMask);addChild(entryActions);
   up=OriginalUI.actionButton("older",function():void{scrollY=Math.max(0,scrollY-120);});scrollControls.addChild(up);
   down=OriginalUI.actionButton("newer",function():void{scrollY=Math.min(maxScroll,scrollY+120);});scrollControls.addChild(down);visible=false;
  }
  private function find(o:DisplayObject,depth:int=0):DisplayObjectContainer {
   if(!o||depth>8||!o.visible)return null;
   if("loginScreen" in o&&"bigLeaf" in o||"holder" in o&&"title_iw" in o&&"nextBut" in o)return o as DisplayObjectContainer;
   if(o is DisplayObjectContainer){var c:DisplayObjectContainer=o as DisplayObjectContainer;for(var i:int=0;i<c.numChildren;i++){var found:DisplayObjectContainer=find(c.getChildAt(i),depth+1);if(found)return found;}}return null;
  }
  private function remember(o:DisplayObject):void{if(o&&!states[o])states[o]={matrix:o.transform.matrix.clone(),scroll:o.scrollRect,bounds:o.getBounds(o),parent:o.parent,index:o.parent?o.parent.getChildIndex(o):0};}
  private function position(o:DisplayObject,x:Number,y:Number,sx:Number,sy:Number):void {if(!o)return;remember(o);transformObject(o,x,y,sx,sy);}
  private function show(o:DisplayObject,value:Boolean):void {if(!o)return;remember(o);if(!("visible" in states[o]))states[o].visible=o.visible;o.visible=value;}
  private function fit(o:DisplayObject,r:Rectangle,stretch:Boolean=false,max:Number=3):void {
   if(!o)return;remember(o);var b:Rectangle=states[o].bounds;if(!b.width||!b.height)return;
   var sx:Number=Math.min(max,r.width/b.width),sy:Number=Math.min(max,r.height/b.height);if(!stretch)sx=sy=Math.min(sx,sy);
   if(states[o].matrix.a<0)sx=-sx;if(states[o].matrix.d<0)sy=-sy;
   position(o,r.x+(r.width-b.width*sx)/2-b.x*sx,r.y+(r.height-b.height*sy)/2-b.y*sy,sx,sy);
  }
  public function reset():void {
   if(resetting)return;resetting=true;
   try {
   entryActions.reset();actionLeaf=null;actionW=actionH=-1;actionFrame=-1;
   if(loginInput){loginInput.dispose();loginInput=null;}
   form=null;
   if(root){root.removeEventListener(MouseEvent.MOUSE_WHEEL,wheel,true);root.removeEventListener(MouseEvent.MOUSE_DOWN,pressed,true);root.removeEventListener(MouseEvent.CLICK,clicked,true);}
   if(stage){stage.removeEventListener(MouseEvent.MOUSE_MOVE,moved);stage.removeEventListener(MouseEvent.MOUSE_UP,released);}
   for(var key:Object in states){var o:DisplayObject=key as DisplayObject;o.transform.matrix=states[o].matrix;o.scrollRect=states[o].scroll;if("visible" in states[o])o.visible=states[o].visible;
    if(o is TextField&&"format" in states[o]){var t:TextField=o as TextField;t.embedFonts=states[o].embedded;t.width=states[o].width;t.height=states[o].height;t.defaultTextFormat=states[o].format;t.text=states[o].text;t.setTextFormat(states[o].format);}
   }
   var order:Array=[];for(key in states)order.push({item:key,state:states[key]});
   // Restore siblings in original order after lifting the live controls above scenery.
   order.sort(function(a:Object,b:Object):Number{return a.state.index-b.state.index;});
   for each(var record:Object in order){o=record.item;if(o.parent==record.state.parent&&o.parent)o.parent.setChildIndex(o,Math.min(record.state.index,o.parent.numChildren-1));}
   scrollControls.mask=null;revealMask.graphics.clear();states=new Dictionary(true);root=null;selectorPage=null;visible=false;scrollY=maxScroll=0;drag=null;
   }finally{resetting=false;}
  }
  public function update(game:DisplayObject,w:Number,h:Number):Boolean {
   if(resetting)return false;
   var found:DisplayObjectContainer=find(game);
   if(found!=root){reset();root=found;
    if(root){kind="loginScreen" in root?"login":"selector";root.addEventListener(MouseEvent.MOUSE_WHEEL,wheel,true);root.addEventListener(MouseEvent.MOUSE_DOWN,pressed,true);root.addEventListener(MouseEvent.CLICK,clicked,true,2000);if(stage){stage.addEventListener(MouseEvent.MOUSE_MOVE,moved);stage.addEventListener(MouseEvent.MOUSE_UP,released);}}
   }
   if(!root)return false;screenW=w;screenH=h;visible=true;
   up.x=w-60;up.y=8;down.x=w-60;down.y=62;
   if(kind=="selector")selector();else login();
   up.visible=down.visible=false;return true;
  }
  private function login():void {
   var native:Object=root,showForm:Boolean=native.loginScreen&&native.loginScreen.visible;
   if(showForm&&!loginInput)loginInput=new MobileLoginInput(native.loginScreen);
   // Keep the initial authored framing throughout landing/login. The desktop
   // page is taller than a landscape phone; it must not become a draggable page.
   var scale:Number=Math.max(screenW/960,screenH>screenW?0:screenH/600);
   maxScroll=0;scrollY=0;
   position(root,(screenW-960*scale)/2,0,scale,scale);
   if("bannerLoader" in native)show(native.bannerLoader,false);
   for each(var obsolete:String in ["leaf1","leaf2","leaf3","leaf5","leaf7","leafElite"])
    if(obsolete in native&&native[obsolete] is DisplayObject)show(native[obsolete],false);
   entryActions.update(root,screenW,screenH);
   // The old card leaf sat below the phone crop. Reuse the cleared left
   // promotion area so account management remains visible and reachable.
   var entryFrame:int=root is MovieClip?MovieClip(root).currentFrame:0;
   if("leaf4" in native&&native.leaf4&&(actionLeaf!=native.leaf4||actionW!=screenW||actionH!=screenH||actionFrame!=entryFrame)){
    fit(native.leaf4,screenH>screenW?new Rectangle(24,96,160,100):new Rectangle(28,Math.max(96,screenH*0.38),Math.min(200,screenW*0.25),Math.min(140,screenH*0.38)),false,1.2);
    actionLeaf=native.leaf4;actionW=screenW;actionH=screenH;actionFrame=entryFrame;
   }
   // The source timeline owns the transition into frame 90. Never capture its
   // intermediate matrices, and never resize individual native form children.
   // Wide screens already fit the authored leaf and its animation together.
   // Repositioning only at frame 90 makes the completed transition jump.
   if(showForm&&screenH>screenW&&(!(root is MovieClip)||MovieClip(root).currentFrame==90)){
    form=native.loginScreen;remember(form);remember(native.bigLeaf);
    // Promotional QR artwork sits in the form's expanded mobile area.
    if("appIcon" in native)show(native.appIcon,false);
    var portrait:Boolean=screenH>screenW;
    var area:Rectangle=portrait?new Rectangle(12,Math.max(80,(screenH-365)/2),screenW-24,365):new Rectangle(Math.max(12,screenW-540),8,Math.min(524,screenW-24),screenH-16);
    var panelScale:Number=Math.min(area.width/LOGIN_PANEL.width,area.height/LOGIN_PANEL.height);
    var x:Number=area.x+(area.width-LOGIN_PANEL.width*panelScale)/2;
    var y:Number=area.y+(area.height-LOGIN_PANEL.height*panelScale)/2;
    mapLoginPart(native.bigLeaf,x,y,panelScale);mapLoginPart(form,x,y,panelScale);
    maxScroll=0;scrollY=0;
   }else if(form){
    for each(var original:DisplayObject in [form,native.bigLeaf])if(states[original]){original.transform.matrix=states[original].matrix;delete states[original];}
    form=null;
    if("appIcon" in native&&states[native.appIcon]&&"visible" in states[native.appIcon])native.appIcon.visible=states[native.appIcon].visible;
   }
  }
  private function mapLoginPart(o:DisplayObject,x:Number,y:Number,scale:Number):void {
   var m:Matrix=states[o].matrix;
   var a:Point=loginPoint(o,x+(m.tx-LOGIN_PANEL.x)*scale,y+(m.ty-LOGIN_PANEL.y)*scale);
   var b:Point=loginPoint(o,x+(m.tx+m.a-LOGIN_PANEL.x)*scale,y+(m.ty+m.b-LOGIN_PANEL.y)*scale);
   var c:Point=loginPoint(o,x+(m.tx+m.c-LOGIN_PANEL.x)*scale,y+(m.ty+m.d-LOGIN_PANEL.y)*scale);
   o.transform.matrix=new Matrix(b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y,a.x,a.y);
  }
  private function loginPoint(o:DisplayObject,x:Number,y:Number):Point{return o.parent.globalToLocal(localToGlobal(new Point(x,y)));}
  private function selector():void {
   var native:Object=root,scale:Number=Math.max(screenW/960,screenH/600);
   var controls:Array=["title_iw","title_en","title_fr","holder","prevBut","nextBut","countText","premiumPopup","newbiesPop","noNewbiePop"];
   for each(var control:String in controls)remember(native[control]);
   // Keep the authored display depths: the parchment timeline mask covers
   // titles, holder and page navigation until its roll has revealed them.
   position(root,(screenW-960*scale)/2,(screenH-600*scale)/2,scale,scale);
   for each(var id:String in ["title_iw","title_en","title_fr"])if(native[id].visible)fit(native[id],new Rectangle(56,12,screenW-112,64));
   var capacity:int=MobileServerLayout.calculate(screenW,screenH,0,1).capacity;
   if("setMobilePageCapacity" in native)native.setMobilePageCapacity(capacity);
   var holder:DisplayObjectContainer=native.holder,page:DisplayObjectContainer=holder.numChildren?holder.getChildAt(0) as DisplayObjectContainer:null;
   if(page!=selectorPage){selectorPage=page;scrollY=0;}
   var pages:int="mobilePageCount" in native?int(native.mobilePageCount):1;
   var layout:Object=MobileServerLayout.calculate(screenW,screenH,page?page.numChildren:0,pages),area:Rectangle=layout.area;
   position(holder,area.x,area.y,1,1);remember(holder);holder.scrollRect=new Rectangle(0,0,area.width,area.height);
   maxScroll=layout.maxScroll;scrollY=Math.min(scrollY,maxScroll);
   if(page){remember(page);page.x=0;page.y=-scrollY;
     for(var i:int=0;i<page.numChildren;i++){
      var slot:DisplayObject=page.getChildAt(i);if(!states[slot]){remember(slot);states[slot].bounds=visibleBounds(slot);}
      var rect:Rectangle=layout.slots[i].clone();rect.offset(area.x,area.y-scrollY);fit(slot,rect,false,5);
     }
   }
   var curtain:DisplayObject=null;
   for(var childIndex:int=0;childIndex<root.numChildren;childIndex++){
    var child:DisplayObject=root.getChildAt(childIndex),authored:Rectangle=child.getBounds(child);
    if(Math.abs(authored.width-649)<2&&Math.abs(authored.height-481)<2&&Math.abs(child.x-479.5)<1){curtain=child;break;}
   }
   revealMask.graphics.clear();revealMask.graphics.beginFill(0);
   if(curtain){var revealed:Rectangle=curtain.getBounds(this);revealed.height=Math.max(0,revealed.height-28*scale);revealMask.graphics.drawRect(revealed.x,revealed.y,revealed.width,revealed.height);}
   revealMask.graphics.endFill();scrollControls.mask=revealMask;
   up.x=area.right+4;down.x=area.right+4;up.y=area.y;down.y=area.bottom-48;
   show(native.prevBut,pages>1);show(native.nextBut,pages>1);show(native.countText,pages>1);
   fit(native.prevBut,new Rectangle(screenW/2-94,screenH-58,44,44));fit(native.nextBut,new Rectangle(screenW/2+50,screenH-58,44,44));
   if(pages>1){
    var counter:TextField=native.countText;
    if(!("format" in states[counter])){states[counter].embedded=counter.embedFonts;states[counter].format=counter.defaultTextFormat;states[counter].text=counter.text;states[counter].width=counter.width;states[counter].height=counter.height;}
    var fmt:TextFormat=counter.defaultTextFormat;fmt.size=24;fmt.align=TextFormatAlign.CENTER;
    counter.embedFonts=false;counter.defaultTextFormat=fmt;counter.text=String(native.mobileCurrentPage)+" / "+pages;counter.setTextFormat(fmt);counter.width=90;counter.height=40;
    position(counter,screenW/2-45,screenH-55,1,1);
   }
   for each(id in ["premiumPopup","newbiesPop","noNewbiePop"])if(native[id].visible)fit(native[id],new Rectangle(24,24,screenW-48,screenH-48));
  }
  private function visibleBounds(o:DisplayObject):Rectangle {
   var b:Rectangle=o.getBounds(o);if(b.width<1||b.height<1||b.width>2048||b.height>2048)return b;
   var pixels:BitmapData=new BitmapData(Math.ceil(b.width)+4,Math.ceil(b.height)+4,true,0);
   pixels.draw(o,new Matrix(1,0,0,1,2-b.x,2-b.y));
   var ink:Rectangle=pixels.getColorBoundsRect(0xFF000000,0,false);pixels.dispose();
   if(ink.isEmpty())return b;ink.offset(b.x-2,b.y-2);return ink;
  }
  private function wheel(e:MouseEvent):void{if(maxScroll){scrollY=Math.max(0,Math.min(maxScroll,scrollY-e.delta*28));e.stopImmediatePropagation();}}
  private function pressed(e:MouseEvent):void{if(!maxScroll||e.target is TextField&&TextField(e.target).type==TextFieldType.INPUT)return;drag=globalToLocal(new Point(e.stageX,e.stageY));last=drag.clone();dragged=false;}
  private function moved(e:MouseEvent):void{if(!drag)return;var p:Point=globalToLocal(new Point(e.stageX,e.stageY));if(Point.distance(p,drag)>8)dragged=true;if(dragged)scrollY=Math.max(0,Math.min(maxScroll,scrollY+last.y-p.y));last=p;}
  private function released(e:MouseEvent):void{drag=null;}
  private function clicked(e:MouseEvent):void{if(kind=="login"&&entryActions.handle(e))return;if(dragged){e.stopImmediatePropagation();dragged=false;}}
 }
}
