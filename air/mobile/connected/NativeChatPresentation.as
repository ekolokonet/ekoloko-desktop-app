package {
 import flash.display.*;import flash.geom.*;import flash.text.*;
 /** Fixed end caps, real ChatInput field/handlers, and a separate physical clip. */
 public final class NativeChatPresentation {
  private var chat:DisplayObjectContainer,field:TextField,skin:DisplayObject,space:DisplayObject,position:Function;
  private var holder:Sprite=new Sprite(),background:Sprite,parent:DisplayObjectContainer,index:int,alpha:Number;
  private var width:Number=-1,height:Number=-1;
  private var originalFormat:TextFormat;
  private var nativeMode:Boolean,preview:TextField,hint:TextField,hintVisible:Boolean;
  private var hit:Sprite,fieldAlpha:Number,fieldMouse:Boolean;
  private var previewFormat:TextFormat,hintFormat:TextFormat,draft:String="",composing:Boolean=false,previewReady:Boolean=false;
  private var clipper:Shape=new Shape(),originalMask:DisplayObject,skinVisible:Boolean;
  public function NativeChatPresentation(owner:DisplayObjectContainer,input:TextField,art:DisplayObject,coordinateSpace:DisplayObject,setPosition:Function,nativePreview:Boolean=false){
   chat=owner;field=input;skin=art;space=coordinateSpace;position=setPosition;alpha=skin.alpha;skinVisible=skin.visible;originalMask=chat.mask;
   originalFormat=field.defaultTextFormat;fieldAlpha=field.alpha;fieldMouse=field.mouseEnabled;
   parent=field.parent;index=parent.getChildIndex(field);chat.addChild(holder);holder.addChild(field);
   holder.name="mobileChatTextViewport";holder.mouseEnabled=nativePreview;
   nativeMode=nativePreview;
   if(nativeMode){
    // Flash input is only the legacy validation/delivery carrier. A DYNAMIC
    // text display cannot summon a competing iOS editor or vanish on blur.
    preview=new TextField();preview.name="mobileChatDraftPreview";preview.type=TextFieldType.DYNAMIC;
    preview.selectable=false;preview.mouseEnabled=false;preview.embedFonts=field.embedFonts;
    previewFormat=field.defaultTextFormat;previewFormat.align=TextFormatAlign.RIGHT;
    hint=chat.getChildByName("instructionsText") as TextField;
    if(hint){hintVisible=hint.visible;hintFormat=hint.defaultTextFormat;hintFormat.align=TextFormatAlign.RIGHT;hint.visible=false;}
    holder.addChild(preview);field.mouseEnabled=false;field.alpha=0;
    hit=new Sprite();hit.name="mobileChatOpenTarget";hit.mouseChildren=false;chat.addChild(hit);
   }
  }
  public function refresh(rect:Rectangle,sendLeft:Number):Rectangle {
   // Trim only the blue outer padding in keyboard mode, keeping the original
   // white opening/text height. Scaling the whole skin would clip 18pt input.
   var skinHeight:Number=rect.height<40?46:rect.height,crop:Number=(skinHeight-rect.height)/2;
   if(width!=rect.width||height!=rect.height){
    if(background)chat.removeChild(background);
    skin.visible=true;skin.alpha=1;background=OriginalUI.chatBackground(rect.width,skinHeight,skin);skin.alpha=0;skin.visible=false;
    chat.addChildAt(background,0);width=rect.width;height=rect.height;
    clipper.graphics.clear();clipper.graphics.beginFill(0);clipper.graphics.drawRect(0,0,width,height);clipper.graphics.endFill();
   }
   if(clipper.parent!=chat.parent)chat.parent.addChild(clipper);
   position(clipper,rect.x,rect.y,1,1);chat.mask=clipper;
   position(background,rect.x,rect.y-crop,1,1);
   var input:Rectangle=NativeChatGeometry.inputBounds(background,space,sendLeft);
   position(holder,input.x,input.y,1,1);var clip:Rectangle=new Rectangle(0,0,input.width,input.height);if(!holder.scrollRect||!holder.scrollRect.equals(clip))holder.scrollRect=clip;
   // Width/height are local to a 1:1 child, never a counter-scaled TextField.
   var matrix:Matrix=field.transform.matrix;
   if(matrix.a!=1||matrix.b!=0||matrix.c!=0||matrix.d!=1||matrix.tx!=0||matrix.ty!=0)field.transform.matrix=new Matrix();
   NativeChatGeometry.constrain(field,input,false);
   var format:TextFormat=field.defaultTextFormat;
   if(format.align!=TextFormatAlign.RIGHT){format.align=TextFormatAlign.RIGHT;field.defaultTextFormat=format;field.setTextFormat(format);}
   if(nativeMode){
    hit.graphics.clear();hit.graphics.beginFill(0,0);hit.graphics.drawRect(0,0,Math.max(0,sendLeft-rect.x-2),rect.height);hit.graphics.endFill();
    position(hit,rect.x,rect.y,1,1);
    NativeChatGeometry.constrain(preview,input,false);field.alpha=0;
   }
   return input;
  }
  public function showDraft(text:String,editing:Boolean):void {
   if(!nativeMode)return;
   if(previewReady&&draft==text&&composing==editing)return;
   previewReady=true;draft=text;composing=editing;
   var placeholder:Boolean=draft.length==0;
   var value:String=placeholder&&hint?hint.text:draft;
   var format:TextFormat=placeholder&&hintFormat?hintFormat:previewFormat;
   preview.defaultTextFormat=format;
   if(preview.text!=value){preview.text=value;preview.setTextFormat(format);}
   preview.visible=!composing;field.alpha=0;
   if(hint)hint.visible=false;
  }
  public function dispose():void {
   if(hint)hint.visible=hintVisible;
   field.alpha=fieldAlpha;field.mouseEnabled=fieldMouse;if(hit&&hit.parent)hit.parent.removeChild(hit);
   chat.mask=originalMask;if(clipper.parent)clipper.parent.removeChild(clipper);
   skin.alpha=alpha;skin.visible=skinVisible;parent.addChildAt(field,Math.min(index,parent.numChildren));
   field.defaultTextFormat=originalFormat;field.setTextFormat(originalFormat);
   if(background&&background.parent)background.parent.removeChild(background);
   if(holder.parent)holder.parent.removeChild(holder);
  }
 }
}
