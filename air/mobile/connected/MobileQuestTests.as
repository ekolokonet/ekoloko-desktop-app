package {
 import flash.display.*;import flash.events.*;import flash.text.*;import flash.geom.*;import flash.filesystem.*;import flash.utils.*;import flash.desktop.NativeApplication;
 public final class MobileQuestTests extends Sprite {
  [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="QuestGroupSlotMC")] private var Group:Class;
  [Embed(source="../../build/mobile-lab/assets/ui.swf",symbol="QuestSubGroupSlotMC")] private var Sub:Class;
  private var panel:DisplayObjectContainer,adapter:MobileQuestPanel,group:DisplayObject,sub:DisplayObject;
  public function MobileQuestTests(){
   loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR,function(e:UncaughtErrorEvent):void{e.preventDefault();trace("QUEST_LAYOUT_FAIL "+e.error);NativeApplication.nativeApplication.exit(2);});
   panel=new OriginalUI.QuestPanel();GameArtwork.stopTree(panel);addChild(panel);
   var slots:Object=Object(panel).groupSlotsContainer;var gs:Sprite=new Sprite(),ss:Sprite=new Sprite();slots.groupHolder.addChild(gs);slots.subGroupHolder.addChild(ss);
   for(var i:int=0;i<9;i++){
    var row:MovieClip=new Group();GameArtwork.stopTree(row);var wrapper:QuestTestSlot=new QuestTestSlot();wrapper.y=i*65;wrapper.addChild(row);gs.addChild(wrapper);label(row.text1,i==0?"חוות הירח":"משימה "+(i+1),16);row.text2.text="";wrapper["getGroupType"]=function():int{return 0;};wrapper["getId"]=function():int{return 1;};if(i==0)group=wrapper;
   }
   for(i=0;i<8;i++){
    row=new Sub();GameArtwork.stopTree(row);wrapper=new QuestTestSlot();wrapper.y=i*55;wrapper.addChild(row);ss.addChild(wrapper);label(row.text1,"חקלאות כללית "+(i+1),14);row.text2.text="";wrapper["questTask"]={};wrapper["isUnavaliableState"]=false;if(i==0)sub=wrapper;
   }
   var q:Object=panel;q.noQuests.visible=false;q.premiumImage.visible=false;q.targetHolder.visible=false;q.questStatusOnlyData.visible=false;
   label(q.storylineBut.theText,"משימות דחופות\nלהצלת אקולוקו",18);label(q.challangeBut.theText,"אתגרים וכיף\nלשעות הפנאי",18);
   label(q.groupTitle,"חוות הירח",26);label(q.subGroupTitle,"חקלאות כללית",20);
   label(q.groupDescription,"אחת מהחזיתות הגדולות ביותר שיש באקולוקו היא הזכות ליישב ירח משלכם. על הירח תוכלו להקים בית וחווה חקלאית ולייצר מזון וחמצן לתושבי אקולוקו.",16);
   label(q.questSubgroupData.subGroupText,"כדי להתחיל לעבוד על החווה, הגיעו לצ׳רלס והקשיבו להוראות. כאן נשאר מקום לכל תיאור המשימה בלי להקטין את האותיות.",16);
   label(q.questSubgroupData.statusText,"בכדי לקבל את המשימה הזאת עליכם להגיע לצ׳רלס",16);label(q.npcName,"צ׳רלס",14);
   label(q.helpBut.txt,"הקליקו כאן לקבלת הכוונה למשימה",14);
   q.npcHolder.addChild(new GameArtwork.Resident());GameArtwork.stopTree(q.npcHolder);
   adapter=new MobileQuestPanel(panel);adapter.refresh(796,334);capture("landscape",796,334);
   adapter.refresh(366,798);capture("portrait-groups",366,798);
   group.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));
   setTimeout(function():void{capture("portrait-tasks",366,798);sub.dispatchEvent(new MouseEvent(MouseEvent.CLICK,true));setTimeout(function():void{
    capture("portrait-detail",366,798);
    adapter.refresh(619,319);capture("small-landscape",619,319);
    adapter.refresh(1000,740);capture("tablet",1000,740);
    var nativeText:String=q.groupDescription.text;adapter.dispose();
    if(q.groupTitle.parent!=panel||slots.groupHolder.parent!=slots)throw new Error("original_parents_not_restored");
    if(q.groupDescription.text!=nativeText)throw new Error("native_text_modified");
    trace("QUEST_LAYOUT_PASS six_renders original_parents_restored=true native_text_preserved=true");NativeApplication.nativeApplication.exit(0);
   },100);},100);
  }
  private function label(t:TextField,value:String,size:Number):void{t.embedFonts=false;t.defaultTextFormat=new TextFormat("Arial",size,0x25172e,true,null,null,null,null,"right");t.text=value;t.setTextFormat(t.defaultTextFormat);}
  private function capture(name:String,w:int,h:int):void{
   var pixels:BitmapData=new BitmapData(w*2,h*2,false,0x285f35);pixels.draw(panel,new Matrix(2,0,0,2));var target:File=File.applicationStorageDirectory.resolvePath("quest-"+name+".png");var stream:FileStream=new FileStream();stream.open(target,FileMode.WRITE);stream.writeBytes(pixels.encode(pixels.rect,new PNGEncoderOptions()));stream.close();pixels.dispose();trace("QUEST_RENDER "+target.nativePath);
  }
 }
}
