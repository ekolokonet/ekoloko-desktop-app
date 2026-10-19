package {
 import flash.display.*;import flash.geom.*;
 /** Fit the complete original vault dialog, including its message and buttons. */
 public final class NativeSecurityPopupLayout {
  public static function fit(popup:DisplayObjectContainer,area:Rectangle,position:Function):Boolean {
   if(!popup||!popup.visible||popup.numChildren==0)return false;
   var bounds:Rectangle=contentBounds(popup);
   if(bounds.isEmpty())return false;
   var scale:Number=Math.min(1.65,area.width/bounds.width,area.height/bounds.height);
   position(popup,area.x+(area.width-bounds.width*scale)/2-bounds.x*scale,
    area.y+(area.height-bounds.height*scale)/2-bounds.y*scale,scale,scale);
   return true;
  }
  public static function contentBounds(popup:DisplayObjectContainer):Rectangle {
   if(popup.numChildren==1){
    var dialog:DisplayObject=popup.getChildAt(0);
    if("okBut" in dialog&&"message" in dialog&&"linkToForm" in dialog){
     // Authored SecurityCodeErrorMessagePopupMC card + safe icon. Its 960x600
     // scrim and oversized glow are decorative, not the dialog's fit bounds.
     var card:Rectangle=new Rectangle(236,168,518,313);
     var a:Point=popup.globalToLocal(dialog.localToGlobal(card.topLeft));
     var b:Point=popup.globalToLocal(dialog.localToGlobal(card.bottomRight));
     return new Rectangle(a.x,a.y,b.x-a.x,b.y-a.y);
    }
   }
   return popup.getBounds(popup);
  }
 }
}
