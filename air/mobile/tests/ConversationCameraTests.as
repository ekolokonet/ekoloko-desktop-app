package {
 import com.vtweens.components.chat.ChatBaloon;
 import flash.display.*;import flash.geom.*;import flash.desktop.NativeApplication;
 public class ConversationCameraTests extends Sprite {
  private var checks:int=0;
  private function check(ok:Boolean,label:String):void{if(!ok)throw new Error(label);checks++;}
  private function projected(r:Rectangle,c:Object):Rectangle{return new Rectangle(c.x+r.x*c.scale,c.y+r.y*c.scale,r.width*c.scale,r.height*c.scale);}
  private function coversRoom(view:Rectangle,camera:Object):Boolean {
   var room:Rectangle=projected(new Rectangle(0,0,960,600),camera);room.inflate(.0000001,.0000001);return room.containsRect(view);
  }
  public function ConversationCameraTests(){
   try {
    var focusGate:MobileInputFocus=new MobileInputFocus();focusGate.begin();
    check(!focusGate.complete()&&focusGate.commit(),'synchronous_complete_focus_after_layout');
    for(var focusEvent:int=0;focusEvent<1000;focusEvent++)check(!focusGate.complete(),'viewport_complete_never_refocuses');
    focusGate.close();check(!focusGate.complete()&&!focusGate.commit(),'dismiss_ignores_late_complete');
    focusGate.begin();check(!focusGate.commit()&&focusGate.complete(),'asynchronous_complete_focus_once');
    focusGate.close();focusGate.begin();focusGate.close();check(!focusGate.complete()&&!focusGate.commit(),'closed_during_open_stays_closed');
    focusGate.begin(true);check(focusGate.commit()&&!focusGate.complete(),'hidden_attached_editor_reopens_without_complete');
    for each(var insetDensity:Number in [1,2,3]){
     var nativeScreen:Rectangle=new Rectangle(0,0,932*insetDensity,430*insetDensity);
     for each(var leftNotch:Boolean in [true,false]){
      var nativeSafe:Rectangle=new Rectangle((leftNotch?59:0)*insetDensity,0,(932-59)*insetDensity,409*insetDensity);
      var inset:Object=MobileLayout.safeInsets(932,430,nativeScreen,nativeSafe,{left:24,right:24,top:8,bottom:12});
      check(leftNotch?inset.left>=63:inset.right>=63,'dynamic_island_clear_on_either_side');
      var safeLayout:Object=MobileLayout.calculate(932,430,inset,new Rectangle(0,206,932,224),true);
      check(safeLayout.composer.x>=inset.left&&safeLayout.composer.right<=932-inset.right,'composer_controls_inside_native_safe_area');
     }
    }
    // Desktop/ADL uses stage coordinates, including SHOW_ALL offsets.
    for each(var dims:Array in [[932,430],[844,390],[375,812],[430,932],[1024,768]]){
     var w:Number=dims[0],h:Number=dims[1],outer:Number=Math.min(w/960,h/600);
     var space:Sprite=new Sprite();space.x=(960-w/outer)/2;space.y=(600-h/outer)/2;space.scaleX=space.scaleY=1/outer;addChild(space);
     var expected:Rectangle=new Rectangle(0,h*.52,w,h*.48);
     var a:Point=space.localToGlobal(expected.topLeft),b:Point=space.localToGlobal(expected.bottomRight);
     var actual:Rectangle=MobileConversationCamera.keyboardBounds(space,new Rectangle(a.x,a.y,b.x-a.x,b.y-a.y),w,h);
     check(Math.abs(actual.y-expected.y)<.1&&Math.abs(actual.height-expected.height)<.1&&Math.abs(actual.width-w)<.1,'keyboard_coordinates_'+w);
     var layout:Object=MobileLayout.calculate(w,h,{left:24,right:24,top:8,bottom:12},actual,true);
     check(layout.composer.bottom<=actual.y&&Math.abs(layout.viewport.bottom-actual.y)<.001,'composer_above_keyboard_'+w);
     check(MobileConversationCamera.keyboardBounds(space,new Rectangle(),w,h).isEmpty(),'hardware_keyboard_'+w);
     removeChild(space);
    }
    // Physical iPhone 14 Pro Max capture: 2796x1290 native pixels, keyboard
    // y=618 height=672. A stage conversion incorrectly produced an empty rect.
    var retinaSpace:Sprite=new Sprite();retinaSpace.x=-170;retinaSpace.y=-212;
    retinaSpace.scaleX=retinaSpace.scaleY=1.35465;addChild(retinaSpace);
    var retina:Rectangle=MobileConversationCamera.keyboardBounds(retinaSpace,new Rectangle(0,618,2796,672),932,430,3);
    check(retina.equals(new Rectangle(0,206,932,224)),'physical_iphone_keyboard_sample');
    var phoneLayout:Object=MobileLayout.calculate(932,430,{left:24,right:24,top:8,bottom:12},retina,true);
    check(phoneLayout.viewport.bottom==206&&phoneLayout.composer.bottom==204,'physical_keyboard_activates_camera_and_exposes_dismiss_button');
    check(phoneLayout.compactComposer&&phoneLayout.composer.height==36&&phoneLayout.composer.y==168,'compact_composer_recovers_twelve_points');
    var compactSafe:Rectangle=new Rectangle(32,10,868,phoneLayout.composer.y-18);
    var measuredOwner:Rectangle=new Rectangle(507,264,80,151);
    var compactCamera:Object=MobileConversationCamera.target(phoneLayout.viewport,compactSafe,932/960,measuredOwner,[]);
    check(compactSafe.containsRect(projected(measuredOwner,compactCamera)),'measured_physical_avatar_fits_compact_safe_area');
    for each(dims in [[932,430],[430,932],[844,390],[390,844]]){
     for each(var density:Number in [2,3]){
      w=dims[0];h=dims[1];
      var nativeRect:Rectangle=new Rectangle(0,h*.52*density,w*density,h*.48*density);
      actual=MobileConversationCamera.keyboardBounds(retinaSpace,nativeRect,w,h,density);
      check(Math.abs(actual.y-h*.52)<.001&&Math.abs(actual.bottom-h)<.001&&Math.abs(actual.width-w)<.001,'native_keyboard_both_landscape_orientations_and_portrait');
      check(MobileConversationCamera.keyboardBounds(retinaSpace,new Rectangle(),w,h,density).isEmpty(),'native_keyboard_dismissed');
     }
    }
    removeChild(retinaSpace);
    var view:Rectangle=new Rectangle(0,0,844,230),safe:Rectangle=new Rectangle(32,10,780,168);
    var own:Rectangle=new Rectangle(460,310,90,155),peer:Rectangle=new Rectangle(570,315,100,150);
    var target:Object=MobileConversationCamera.target(view,safe,1,own,[peer]);
    check(safe.containsRect(projected(own,target))&&safe.containsRect(projected(peer,target)),'owner_and_nearby_bubbles_fit');
    var alone:Object=MobileConversationCamera.target(view,safe,1,own,[]);
    var distant:Object=MobileConversationCamera.target(view,safe,1,own,[new Rectangle(900,0,300,500)]);
    check(alone.x==distant.x&&alone.y==distant.y,'distant_player_cannot_displace_owner');
    var tall:Rectangle=new Rectangle(460,240,90,250),t:Object=MobileConversationCamera.target(view,safe,1,tall,[]);
    check(t.scale==1&&Math.abs(projected(tall,t).top-safe.top)<.001,'tall_subject_keeps_speech_top_without_room_shrink');
    for each(var corner:Rectangle in [new Rectangle(0,0,80,140),new Rectangle(880,450,80,150)]){
     t=MobileConversationCamera.target(view,safe,1,corner,[]);
     check(t.x<=0&&t.y<=0&&t.x+960>=view.width&&t.y+600>=view.height,'room_edges_not_exposed');
    }
    // Every edge/corner, both orientations, multiple zoom levels, including bubbles
    // extending beyond authored room art. Room clipping wins over forced centering.
    for each(dims in [[932,430],[844,390],[375,812],[430,932],[1024,768]]){
     w=dims[0];h=dims[1];
     for each(var zoom:Number in [1,1.35,1.8]){
      var edgeView:Rectangle=new Rectangle(0,0,w,h*.52);
      var edgeSafe:Rectangle=new Rectangle(32,10,w-64,Math.max(32,edgeView.height-68));
      var edgeScale:Number=Math.max(.9,w/960,h/600)*zoom;
      for each(var anchor:Array in [[0,0],[480,0],[960,0],[0,300],[960,300],[0,600],[480,600],[960,600]]){
       var edgeOwner:Rectangle=new Rectangle(anchor[0]-45,anchor[1]-190,90,208);
       var edgeTarget:Object=MobileConversationCamera.target(edgeView,edgeSafe,edgeScale,edgeOwner,[]);
       check(coversRoom(edgeView,edgeTarget),'all_edges_keep_room_coverage');
       // Interpolate from a stale pre-keyboard/rotated camera, then bound every frame.
       var edgeCurrent:Object={x:80,y:120,scale:edgeScale};
       for(var frame:int=0;frame<12;frame++){
        edgeCurrent=MobileConversationCamera.constrain(edgeView,MobileConversationCamera.approach(edgeCurrent,edgeTarget,1000/24));
        check(coversRoom(edgeView,edgeCurrent),'all_edge_transition_frames_covered');
       }
       // Dismissing the keyboard expands the viewport before its return tween ends.
       var fullView:Rectangle=new Rectangle(0,0,w,h);
       var restored:Object=MobileConversationCamera.constrain(fullView,edgeCurrent);
       check(coversRoom(fullView,restored),'dismiss_keyboard_at_edge_covered '+w+'x'+h+' zoom='+zoom+' anchor='+anchor+' room='+projected(new Rectangle(0,0,960,600),restored)+' view='+fullView);
       var rounded:Object={x:Math.round(restored.x*3)/3,y:Math.round(restored.y*3)/3,scale:restored.scale};
       rounded=MobileConversationCamera.constrain(fullView,rounded);
       check(coversRoom(fullView,rounded),'pixel_rounding_cannot_expose_edge');
      }
     }
    }
    // An overview may be smaller than the viewport; center the clipped room without
    // panning into offstage art. The existing world scrollRect stays 960 by 600.
    var overview:Object=MobileConversationCamera.constrain(view,{x:400,y:-100,scale:.3});
    check(overview.x==(view.width-288)/2&&overview.y==(view.height-180)/2,'undersized_overview_is_centered');
    var current:Object={x:0,y:0,scale:1};
    for(var i:int=0;i<90;i++){
     var next:Object=MobileConversationCamera.approach(current,target,1000/60);
     check(next.y<=current.y&&next.y>=target.y&&next.scale==1,'smooth_no_overshoot_'+i);current=next;
    }
    check(Math.abs(current.y-target.y)<.01,'smooth_converges');
    var frozen:Object=MobileConversationCamera.approach(current,{x:50,y:50,scale:2},0);
    check(frozen.x==current.x&&frozen.y==current.y&&frozen.scale==current.scale,'duplicate_layout_same_frame_no_jump');
    // Real collector uses player anchors and actual visible ChatBaloon children.
    var world:Sprite=new Sprite();addChild(world);
    var me:CameraFixturePlayer=new CameraFixturePlayer(),other:CameraFixturePlayer=new CameraFixturePlayer(),far:CameraFixturePlayer=new CameraFixturePlayer();
    world.addChild(me);world.addChild(other);world.addChild(far);me.x=400;me.y=400;other.x=510;other.y=410;far.x=430;far.y=550;
    var collector:MobileConversationFocus=new MobileConversationFocus(),subjects:Object=collector.sample(me,world,1000);
    check(subjects.neighbors.length==1,'same_row_only');
    for(i=0;i<1000;i++)check(collector.sample(me,world,1000+(i%200))===subjects,'stable_frames_reuse_focus_snapshot_without_traversal');
    var bubble:ChatBaloon=new ChatBaloon();me.addChild(bubble);
    subjects=collector.sample(me,world,1200);var reserved:Number=subjects.own.top;
    check(reserved==200,'actual_bubble_included');
    me.removeChild(bubble);subjects=collector.sample(me,world,1400);
    check(subjects.own.top==reserved,'bubble_expiry_does_not_bob_camera');
    collector.reset();subjects=collector.sample(me,world,1600);check(subjects.own.top==280,'new_chat_resets_reserved_bubble');
    trace('CONVERSATION_CAMERA_PASS checks='+checks);NativeApplication.nativeApplication.exit(0);
   }catch(e:Error){trace('CONVERSATION_CAMERA_FAIL '+e);NativeApplication.nativeApplication.exit(1);}
  }
 }
}
import flash.display.Sprite;
class CameraFixturePlayer extends Sprite {public function getPlayerName():String{return 'fixture';}}
