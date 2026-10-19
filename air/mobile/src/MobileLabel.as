package {
    import flash.display.Sprite;
    import flash.text.engine.ElementFormat;
    import flash.text.engine.FontDescription;
    import flash.text.engine.FontLookup;
    import flash.text.engine.TextBlock;
    import flash.text.engine.TextElement;
    import flash.text.engine.TextLine;

    /** TextFormats.init() selects Arial for Hebrew in the original game. */
    public final class MobileLabel extends Sprite {
        public function MobileLabel(text:String,width:Number,size:Number=16,color:uint=0xffffff,align:String="center") {
            mouseEnabled=false;mouseChildren=false;
            var font:FontDescription=new FontDescription("Arial","bold");font.fontLookup=FontLookup.DEVICE;
            var top:Number=0;
            for each(var paragraph:String in text.split("\n")) {
                if(!paragraph.length){top+=size*1.4;continue;}
                var block:TextBlock=new TextBlock(new TextElement(paragraph,new ElementFormat(font,size,color)));block.bidiLevel=1;
                var previous:TextLine=null,line:TextLine;
                while((line=block.createTextLine(previous,width))!=null){
                    line.x=Math.round(align=="right"?width-line.textWidth:align=="left"?0:(width-line.textWidth)/2);
                    line.y=Math.round(top+size);addChild(line);previous=line;top+=size*1.4;
                }
            }
        }
    }
}
