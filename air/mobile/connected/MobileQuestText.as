package {
 import flash.display.Sprite;
 import flash.text.TextField;
 import flash.text.TextFormat;
 import flash.text.engine.*;
 /** Reflow plain native quest strings with the same font family and explicit RTL. */
 public final class MobileQuestText extends Sprite {
  public var contentHeight:Number=0;
  public function MobileQuestText(source:TextField,w:Number,size:Number){
   mouseEnabled=mouseChildren=false;
   var format:TextFormat=source.defaultTextFormat;
   var font:FontDescription=new FontDescription(format.font||"Arial",format.bold?"bold":"normal",format.italic?"italic":"normal");
   font.fontLookup=FontLookup.DEVICE;
   var style:ElementFormat=new ElementFormat(font,size,source.textColor);
   var top:Number=4,inner:Number=Math.max(1,w-12);
   for each(var paragraph:String in source.text.split(/\r\n|\r|\n/)){
    if(!paragraph.length){top+=size*1.35;continue;}
    var block:TextBlock=new TextBlock(new TextElement(paragraph,style));
    block.bidiLevel=/[\u0590-\u05ff]/.test(paragraph)?1:0;
    var previous:TextLine=null,line:TextLine;
    while((line=block.createTextLine(previous,inner))!=null){
     line.x=6+(format.align=="center"?(inner-line.textWidth)/2:format.align=="left"?0:inner-line.textWidth);
     line.y=top+line.ascent;addChild(line);top+=Math.max(size*1.35,line.ascent+line.descent+4);previous=line;
    }
   }
   contentHeight=top+4;filters=source.filters;
  }
 }
}
