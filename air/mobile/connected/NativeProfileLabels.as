package {
 import flash.display.*;import flash.text.*;import flash.text.engine.*;import flash.geom.*;
 /** Mirror the two native Hebrew captions without changing their source values. */
 public final class NativeProfileLabels {
  private var root:DisplayObjectContainer,entries:Array=[];
  public function NativeProfileLabels(owner:DisplayObjectContainer){root=owner;}
  public function refresh():void {
   var fields:Array=[];
   if("seniorityLevelNameText" in root)fields.push(Object(root).seniorityLevelNameText);
   if("securityButton" in root&&Object(root).securityButton&&"lockItemsText" in Object(root).securityButton)fields.push(Object(root).securityButton.lockItemsText);
   for each(var field:TextField in fields){
    if(!field||!field.parent)continue;
    var entry:Object=null;for each(var known:Object in entries)if(known.field==field){entry=known;break;}
    if(!entry){entry={field:field,alpha:field.alpha,view:null,key:""};entries.push(entry);}
    var format:TextFormat=field.defaultTextFormat,size:Number=Number(format.size)||12;
    var key:String=field.text+":"+field.width+":"+field.height+":"+format.font+":"+size+":"+format.bold+":"+format.align+":"+field.textColor;
    if(!/[\u0590-\u05ff]/.test(field.text)){field.alpha=entry.alpha;if(entry.view)entry.view.visible=false;continue;}
    if(entry.key!=key){
     if(entry.view&&entry.view.parent)entry.view.parent.removeChild(entry.view);
     var view:Sprite=new Sprite();view.name="rtl-"+field.name;view.mouseEnabled=view.mouseChildren=false;
     var font:FontDescription=new FontDescription(format.font||"Arial",format.bold?"bold":"normal",format.italic?"italic":"normal");font.fontLookup=FontLookup.DEVICE;
     var style:ElementFormat=new ElementFormat(font,size,field.textColor),top:Number=2,inner:Number=Math.max(1,field.width-4);
     for each(var paragraph:String in field.text.split(/\r\n|\r|\n/)){
      if(!paragraph.length){top+=size;continue;}
      var block:TextBlock=new TextBlock(new TextElement(paragraph,style));block.bidiLevel=1;
      var previous:TextLine=null,line:TextLine;
      while((line=block.createTextLine(previous,inner))!=null){line.x=2+(format.align=="center"?(inner-line.textWidth)/2:format.align=="left"?0:inner-line.textWidth);line.y=top+line.ascent;view.addChild(line);top+=line.ascent+line.descent+Math.max(0,Number(format.leading)||0);previous=line;}
     }
     // Preserve both full lines in short authored fields, without stretching glyphs.
     var scale:Number=Math.min(1,(field.height-4)/Math.max(1,top-2));view.scaleX=view.scaleY=scale;
     var wrapper:Sprite=new Sprite();wrapper.mouseEnabled=wrapper.mouseChildren=false;wrapper.addChild(view);view.x=(field.width-field.width*scale)/2;view.y=(field.height-top*scale)/2;
     wrapper.filters=field.filters;entry.view=wrapper;entry.key=key;field.parent.addChild(wrapper);
    }
    field.alpha=0;entry.view.visible=field.visible;entry.view.alpha=entry.alpha;entry.view.transform.matrix=field.transform.matrix;
   }
  }
  public function dispose():void{for each(var entry:Object in entries){entry.field.alpha=entry.alpha;if(entry.view&&entry.view.parent)entry.view.parent.removeChild(entry.view);}entries=[];}
 }
}
