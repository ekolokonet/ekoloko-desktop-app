package {
 import flash.display.*;
 import flash.events.*;
 import flash.geom.*;
 import flash.text.*;
 import flash.utils.*;

 /** Responsive presentation of the actual QuestMenu instances and selection handlers. */
 public final class MobileQuestPanel {
  private var root:DisplayObjectContainer,original:Dictionary=new Dictionary(true),order:Array=[];
  private var layer:Sprite=new Sprite(),listView:Sprite=new Sprite(),detailView:Sprite=new Sprite(),detailBody:Sprite=new Sprite();
  private var groups:DisplayObjectContainer,subgroups:DisplayObjectContainer,tabs:Array=[],details:Array=[];
  private var close:Sprite,back:Sprite,skin:Sprite,listUp:Sprite,listDown:Sprite,detailUp:Sprite,detailDown:Sprite;
  private var width:Number=0,height:Number=0,step:int=0,split:Boolean=false,signature:String="";
  private var listScroll:Number=0,detailScroll:Number=0,listMax:Number=0,detailMax:Number=0;
  private var down:Point,last:Point,dragArea:String="",dragged:Boolean=false;
  private var detailRect:Rectangle,listRect:Rectangle;
  private var frameStage:Stage,help:DisplayObject,textViews:Dictionary=new Dictionary(true);
  public function MobileQuestPanel(menu:DisplayObjectContainer){
   root=menu;frameStage=root.stage;
   var slots:DisplayObjectContainer=part(root,"groupSlotsContainer") as DisplayObjectContainer;
   groups=part(slots,"groupHolder") as DisplayObjectContainer;subgroups=part(slots,"subGroupHolder") as DisplayObjectContainer;
   for(var i:int=0;i<root.numChildren;i++)remember(root.getChildAt(i));
   remember(root);remember(groups);remember(subgroups);
   // Retain public instance references used by QusetDisplayHandler when changing parents.
   for each(var id:String in ["storylineBut","challangeBut"])tabs.push(part(root,id));
   for each(id in ["groupIconHolder","groupTitle","subGroupTitle","groupDescription","questSubgroupData","questStatusOnlyData","targetHolder","npcHolder","npcName","statusIcon","premiumImage","noQuests"]){
    var item:DisplayObject=part(root,id);if(item){details.push(item);rememberTree(item);}
   }
   for each(var old:DisplayObject in order)if(old.parent==root)old.alpha=0;
   root.addChild(layer);layer.addChild(listView);layer.addChild(detailView);detailView.addChild(detailBody);
   listView.addChild(groups);listView.addChild(subgroups);groups.mask=null;subgroups.mask=null;groups.alpha=subgroups.alpha=1;
   for each(item in details){detailBody.addChild(item);item.alpha=original[item].alpha;}
   for each(item in tabs){layer.addChild(item);item.alpha=original[item].alpha;}
   help=part(root,"helpBut");if(help){detailBody.addChild(help);help.alpha=original[help].alpha;}
   close=OriginalUI.actionButton("close",function():void{var button:DisplayObject=part(root,"closeBut");button.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));});
   back=OriginalUI.actionButton("older",function():void{step=Math.max(0,step-1);listScroll=detailScroll=0;signature="";refresh(width,height);});
   back.accessibilityProperties.name="חזרה לרשימת המשימות";layer.addChild(close);layer.addChild(back);
   listUp=OriginalUI.actionButton("older",function():void{scroll("list",-160);});listDown=OriginalUI.actionButton("newer",function():void{scroll("list",160);});
   detailUp=OriginalUI.actionButton("older",function():void{scroll("detail",-160);});detailDown=OriginalUI.actionButton("newer",function():void{scroll("detail",160);});
   for each(var arrow:Sprite in [listUp,listDown,detailUp,detailDown])layer.addChild(arrow);
   root.addEventListener(MouseEvent.CLICK,clicked,true,1000);
   layer.addEventListener(MouseEvent.MOUSE_DOWN,pressed,true);
   layer.addEventListener(MouseEvent.MOUSE_WHEEL,wheel,true);
   if(frameStage){frameStage.addEventListener(MouseEvent.MOUSE_MOVE,moved);frameStage.addEventListener(MouseEvent.MOUSE_UP,released);}
  }
  private function part(parent:DisplayObjectContainer,id:String):DisplayObject {
   if(!parent)return null;
   if(id in parent&&Object(parent)[id] is DisplayObject)return Object(parent)[id];
   for each(var item:DisplayObject in order)if(item.name==id&&original[item].parent==parent)return item;
   return parent.getChildByName(id);
  }
  private function remember(o:DisplayObject):void {
   if(!o||original[o])return;
   original[o]={parent:o.parent,index:o.parent?o.parent.getChildIndex(o):0,matrix:o.transform.matrix.clone(),alpha:o.alpha,mask:o.mask,scroll:o.scrollRect,visible:o.visible,children:o is DisplayObjectContainer?DisplayObjectContainer(o).mouseChildren:false,
    width:o.width,height:o.height,format:o is TextField?TextField(o).defaultTextFormat:null,wrap:o is TextField?TextField(o).wordWrap:false,multiline:o is TextField?TextField(o).multiline:false,selectable:o is TextField?TextField(o).selectable:false};order.push(o);
  }
  private function rememberTree(o:DisplayObject):void {remember(o);if(o is DisplayObjectContainer){var c:DisplayObjectContainer=o as DisplayObjectContainer;for(var i:int=0;i<c.numChildren;i++)rememberTree(c.getChildAt(i));}}
  public function dispose():void {
   for each(var mirror:Sprite in textViews)if(mirror.parent)mirror.parent.removeChild(mirror);
   root.removeEventListener(MouseEvent.CLICK,clicked,true);layer.removeEventListener(MouseEvent.MOUSE_DOWN,pressed,true);layer.removeEventListener(MouseEvent.MOUSE_WHEEL,wheel,true);
   if(frameStage){frameStage.removeEventListener(MouseEvent.MOUSE_MOVE,moved);frameStage.removeEventListener(MouseEvent.MOUSE_UP,released);}
   for each(var o:DisplayObject in order){var state:Object=original[o];if(o!=root&&state.parent&&o.parent!=state.parent)state.parent.addChildAt(o,Math.min(state.index,state.parent.numChildren));
    o.transform.matrix=state.matrix;o.alpha=state.alpha;o.mask=state.mask;o.scrollRect=state.scroll;
    if(o is DisplayObjectContainer)DisplayObjectContainer(o).mouseChildren=state.children;
    if(tabs.indexOf(o)>=0)o.visible=state.visible;
    if(o is TextField){var t:TextField=o as TextField;t.width=state.width;t.height=state.height;t.defaultTextFormat=state.format;t.setTextFormat(state.format);t.wordWrap=state.wrap;t.multiline=state.multiline;t.selectable=state.selectable;}
   }
   if(layer.parent)layer.parent.removeChild(layer);
  }
  public function refresh(w:Number,h:Number):void {
   width=w;height=h;split=w>=600&&w>h;
   var title:TextField=part(root,"groupTitle") as TextField,description:TextField=part(root,"groupDescription") as TextField;
   var key:String=w+":"+h+":"+step+":"+(title?title.text:"")+":"+(description?description.text:"");
   for each(var d:DisplayObject in details)key+=fingerprint(d);
   if(key!=signature){signature=key;arrange();}
   scrollLists();
  }
  private function fingerprint(o:DisplayObject):String {
   var result:String=":"+o.visible;
   if(o is TextField)return result+":"+TextField(o).text;
   if(o is DisplayObjectContainer){var c:DisplayObjectContainer=o as DisplayObjectContainer;result+=":"+c.numChildren;for(var i:int=0;i<c.numChildren;i++)result+=fingerprint(c.getChildAt(i));}
   return result;
  }
  private function arrange():void {
   if(skin&&skin.parent)skin.parent.removeChild(skin);skin=OriginalUI.panelBackground(width,height);layer.addChildAt(skin,0);
   root.scrollRect=new Rectangle(0,0,width,height);
   close.x=width-56;close.y=4;back.x=8;back.y=4;back.visible=step>0;
   var side:Number=split?Math.min(280,width*.36):width;
   listUp.x=split?side-106:width-164;listDown.x=split?side-54:width-110;listUp.y=listDown.y=4;
   detailUp.x=width-164;detailDown.x=width-110;detailUp.y=detailDown.y=4;
   listRect=new Rectangle(12,118,side-24,height-130);
   detailRect=new Rectangle(split?side+8:12,62,split?width-side-20:width-24,height-74);
   listView.visible=split||step<2;detailView.visible=split||step==2;
   listView.x=listRect.x;listView.y=listRect.y;listView.scrollRect=new Rectangle(0,0,listRect.width,listRect.height);
   detailView.x=detailRect.x;detailView.y=detailRect.y;detailView.scrollRect=new Rectangle(0,0,detailRect.width,detailRect.height);
   for(var i:int=0;i<tabs.length;i++){
    var tab:DisplayObjectContainer=tabs[i] as DisplayObjectContainer;tab.visible=step==0; // Presentation-only; restored on dispose.
    var text:DisplayObject=part(tab,"theText");var crop:Rectangle=text.getBounds(tab);crop.inflate(10,8);tab.scrollRect=crop;
    tab.scaleX=tab.scaleY=Math.min(1,(side-36)/2/crop.width);tab.x=12+i*(side-24)/2;tab.y=58;
   }
   if(step>0){listRect.y=62;listRect.height=height-74;listView.y=listRect.y;listView.scrollRect=new Rectangle(0,0,listRect.width,listRect.height);}
   layoutDetails();scrollLists();
  }
  private function text(o:TextField,x:Number,y:Number,w:Number,size:Number):Number {
   if(!o)return 0;remember(o);
   // Keep the controller-owned fields intact. Authored DefineEditText rectangles
   // retain negative clipping bounds when resized, so render the same text/font
   // into a zero-origin field and refresh it when the native controller changes.
   var mirror:MobileQuestText=textViews[o];if(mirror&&mirror.parent)mirror.parent.removeChild(mirror);
   mirror=new MobileQuestText(o,w,size);textViews[o]=mirror;detailBody.addChild(mirror);
   var nested:Boolean=o.parent!=detailBody;
   mirror.x=x+(nested?o.parent.x:0);mirror.y=y+(nested?o.parent.y:0);mirror.visible=o.visible&&(!nested||o.parent.visible);mirror.alpha=original[o].alpha;o.alpha=0;return mirror.contentHeight;
  }
  private function fit(o:DisplayObject,r:Rectangle):void {
   if(!o)return;var b:Rectangle=o.getBounds(o);if(!b.width||!b.height)return;
   var scale:Number=Math.min(r.width/b.width,r.height/b.height,1);o.scaleX=o.scaleY=scale;o.x=r.x+(r.width-b.width*scale)/2-b.x*scale;o.y=r.y-b.y*scale;
  }
  private function layoutDetails():void {
   var w:Number=detailRect.width,y:Number=8;
   var title:TextField=part(root,"groupTitle") as TextField,sub:TextField=part(root,"subGroupTitle") as TextField,description:TextField=part(root,"groupDescription") as TextField;
   y+=text(title,58,y,w-66,24)+4;y+=text(sub,58,y,w-66,19)+10;
   fit(part(root,"groupIconHolder"),new Rectangle(0,8,50,66));fit(part(root,"statusIcon"),new Rectangle(12,76,26,26));
   y+=text(description,8,y,w-16,17)+14;
   var npc:DisplayObject=part(root,"npcHolder");fit(npc,new Rectangle(0,y,92,134));text(part(root,"npcName") as TextField,0,y+138,96,14);
   var body:DisplayObjectContainer=part(root,"questSubgroupData") as DisplayObjectContainer;
   var status:DisplayObjectContainer=part(root,"questStatusOnlyData") as DisplayObjectContainer;
   var bodyWidth:Number=Math.max(150,w-112),bodyHeight:Number=0;
   if(body){body.scaleX=body.scaleY=1;body.x=104;body.y=y;
    bodyHeight=text(part(body,"subGroupText") as TextField,0,0,bodyWidth,17)+12;
    var st:TextField=part(body,"statusText") as TextField;bodyHeight+=text(st,0,bodyHeight,bodyWidth,17);
    for(var i:int=0;i<body.numChildren;i++){var decoration:DisplayObject=body.getChildAt(i);if(!(decoration is TextField))decoration.alpha=0;}
   }
   if(status){status.scaleX=status.scaleY=1;status.x=104;status.y=y;var sh:Number=text(part(status,"statusText") as TextField,0,0,bodyWidth,17);if(status.visible)bodyHeight=sh;
    for(i=0;i<status.numChildren;i++){decoration=status.getChildAt(i);if(!(decoration is TextField))decoration.alpha=0;}
   }
   var target:DisplayObject=part(root,"targetHolder");fit(target,new Rectangle(104,y,bodyWidth,Math.max(170,detailRect.height-y)));if(target&&target.visible)bodyHeight=Math.max(bodyHeight,target.height);
   var premium:DisplayObject=part(root,"premiumImage");fit(premium,new Rectangle(w-40,0,32,32));
   var none:DisplayObject=part(root,"noQuests");fit(none,new Rectangle(8,8,w-16,detailRect.height-16));
   var total:Number=y+Math.max(166,bodyHeight)+24;fit(help,new Rectangle(8,total,w-16,44));total+=56;detailMax=Math.max(0,total-detailRect.height);detailScroll=Math.min(detailScroll,detailMax);detailBody.y=-detailScroll;
  }
  private function scrollLists():void {
   groups.alpha=step==0?1:0;subgroups.alpha=step>0?1:0;groups.mouseChildren=step==0;subgroups.mouseChildren=step>0;
   var holder:DisplayObjectContainer=step==0?groups:subgroups;
   if(!holder.numChildren)return;
   var content:DisplayObject=holder.getChildAt(0);remember(content);content.y=0;
   var b:Rectangle=content.getBounds(content),scale:Number=Math.min(1.4,(listRect.width-8)/Math.max(180,b.width));
   holder.scaleX=holder.scaleY=scale;holder.x=(listRect.width-b.width*scale)/2-b.x*scale;
   listMax=Math.max(0,b.height*scale-listRect.height);listScroll=Math.max(0,Math.min(listScroll,listMax));holder.y=-b.y*scale-listScroll;
   listUp.visible=listDown.visible=listView.visible&&listMax>0;
   detailUp.visible=detailDown.visible=detailView.visible&&detailMax>0;
  }
  private function clicked(e:MouseEvent):void {
   if(dragged){e.stopImmediatePropagation();dragged=false;return;}
   var o:DisplayObject=e.target as DisplayObject;
   while(o&&o!=root){
    if("getGroupType" in o&&"getId" in o){setTimeout(function():void{step=1;listScroll=detailScroll=0;signature="";refresh(width,height);},0);return;}
    if("questTask" in o&&"isUnavaliableState" in o){if(!Object(o).isUnavaliableState)setTimeout(function():void{if(!split)step=2;detailScroll=0;signature="";refresh(width,height);},0);return;}
    o=o.parent;
   }
  }
  private function pressed(e:MouseEvent):void {
   var target:DisplayObject=e.target as DisplayObject;dragArea=listView.visible&&listView.contains(target)?"list":detailView.visible&&detailView.contains(target)?"detail":"";
   if(dragArea){down=layer.globalToLocal(new Point(e.stageX,e.stageY));last=down.clone();dragged=false;}
  }
  private function moved(e:MouseEvent):void {
   if(!down)return;var p:Point=layer.globalToLocal(new Point(e.stageX,e.stageY));if(Point.distance(p,down)>8)dragged=true;
   if(dragged){scroll(dragArea,last.y-p.y);e.updateAfterEvent();}last=p;
  }
  private function released(e:MouseEvent):void{down=null;dragArea="";setTimeout(function():void{dragged=false;},30);}
  private function wheel(e:MouseEvent):void{var target:DisplayObject=e.target as DisplayObject;if(listView.contains(target)||detailView.contains(target)){scroll(listView.contains(target)?"list":"detail",-e.delta*28);e.stopImmediatePropagation();}}
  private function scroll(area:String,amount:Number):void{if(area=="list"){listScroll=Math.max(0,Math.min(listMax,listScroll+amount));scrollLists();}else{detailScroll=Math.max(0,Math.min(detailMax,detailScroll+amount));detailBody.y=-detailScroll;}}
 }
}
