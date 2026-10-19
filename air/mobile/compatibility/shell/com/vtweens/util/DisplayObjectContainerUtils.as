package com.vtweens.util
{
   import flash.display.DisplayObjectContainer;
   import flash.display.MovieClip;
   
   public class DisplayObjectContainerUtils
   {
      
      public function DisplayObjectContainerUtils()
      {
         super();
      }
      
      public static function stopHierarchy(param1:DisplayObjectContainer) : *
      {
         var _loc4_:* = undefined;
         if(param1 == null)
         {
            return;
         }
         if(param1 is MovieClip)
         {
            (param1 as MovieClip).stop();
         }
         var _loc2_:* = param1.numChildren;
         var _loc3_:* = 0;
         while(_loc3_ < _loc2_)
         {
            _loc4_ = param1.getChildAt(_loc3_);
            if(_loc4_ is DisplayObjectContainer)
            {
               stopHierarchy(_loc4_);
            }
            _loc3_++;
         }
      }
      
      public static function stopAndRemoveHierarchy(param1:DisplayObjectContainer) : *
      {
         var _loc5_:* = undefined;
         if(param1 == null)
         {
            return;
         }
         if(param1 is MovieClip)
         {
            (param1 as MovieClip).stop();
         }
         var _loc2_:* = param1.numChildren;
         var _loc3_:Array = [];
         var _loc4_:* = 0;
         while(_loc4_ < _loc2_)
         {
            _loc3_[_loc4_] = param1.getChildAt(_loc4_);
            _loc4_++;
         }
         // Capture siblings before callbacks can remove or reparent them.
         for each(_loc5_ in _loc3_)
         {
            if(_loc5_ != null && _loc5_.parent == param1)
            {
               if(_loc5_ is DisplayObjectContainer)
               {
                  stopAndRemoveHierarchy(_loc5_);
               }
               // REMOVED handlers may already have retired this branch.
               if(_loc5_.parent == param1)
               {
                  param1.removeChild(_loc5_);
               }
            }
         }
      }
      
      public static function removeChildren(param1:DisplayObjectContainer) : *
      {
         if(!param1)
         {
            return;
         }
         var _loc2_:* = param1.numChildren;
         var _loc3_:* = 0;
         while(_loc3_ < _loc2_)
         {
            param1.removeChildAt(0);
            _loc3_++;
         }
      }
   }
}

