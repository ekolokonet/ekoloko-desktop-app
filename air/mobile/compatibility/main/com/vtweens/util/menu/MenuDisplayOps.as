package com.vtweens.util.menu
{
   import com.greensock.TweenMax;
   import com.vtweens.components.MainMenu;
   import com.vtweens.components.MapPanel;
   import com.vtweens.components.chat.ChangeActivationMenu;
   import com.vtweens.components.helper.HelperControl;
   import com.vtweens.components.helper.HelperMainMenu;
   import com.vtweens.components.helper.HelperQuests;
   import com.vtweens.components.helper.menu.HelperMenuControl;
   import com.vtweens.credits_store.CreditsStorePane;
   import com.vtweens.dataobjects.npc.menu.NPCDataMenu;
   import com.vtweens.dataobjects.quest.menu.QuestMenu;
   import com.vtweens.dataobjects.store.menu.buy.StoreBuyMenu;
   import com.vtweens.dataobjects.store.menu.sell.StoreSellMenu;
   import com.vtweens.util.MainGetter;
   import fl.motion.easing.Linear;
   import flash.display.Sprite;
   import flash.utils.Dictionary;
   import flash.utils.getTimer;
   import flash.filters.DropShadowFilter;
   
   public class MenuDisplayOps
   {
      
      private static const HIDE_POSITION:int = -5;
      
      private static const DROP_EXTENSION:int = 50;
      
      private static const DURATION:Number = 0.8;
      
      private static const SHADOW_FILTER:Array = [new DropShadowFilter(5,45,0,1,10,10,1)];
      
      private static var menu:* = null;
      // Mobile presentation uses one normalized clock. Native tweens retain
      // their original lifecycle callbacks, without a second competing curve.
      private static var mobileMotion:Dictionary = new Dictionary(true);
      public static function mobileMenuOffset(panel:Sprite):Number {
         var state:Object = mobileMotion[panel];
         if(!state) return 0;
         var elapsed:Number = Math.min(1,Math.max(0,(getTimer()-state.started)/(DURATION*1000)));
         // No overshoot-and-clamp plateau at the screen edge. Content keeps its
         // native lifecycle/timing while the mobile curtain settles smoothly.
         var eased:Number = state.opening ? 1-Math.pow(1-elapsed,3) : elapsed*elapsed*elapsed;
         return state.start+(state.end-state.start)*eased;
      }
      private static function trackMobileMotion(panel:Sprite, opening:Boolean):void {
         var previous:Object = mobileMotion[panel];
         var initial:Number = previous ? mobileMenuOffset(panel) : (opening ? -1 : 0);
         mobileMotion[panel] = {started:getTimer(),opening:opening,start:initial,end:opening?0:-1};
      }
      private static function clearMobileMotion(panel:Sprite):void {
         delete mobileMotion[panel];
      }
      
      public function MenuDisplayOps()
      {
         super();
      }
      
      public static function HideMenu(param1:Sprite) : *
      {
         var _loc2_:* = param1;
         if(_loc2_ == null)
         {
            _loc2_ = menu;
         }
         if(_loc2_ != null)
         {
            if(_loc2_ is CreditsStorePane)
            {
               MainGetter.MainCaller.uiLayer.setChatVisible(true);
               MainGetter.MainCaller.SetInCreditsStoreVariable(false);
            }
            else if(_loc2_ is NPCDataMenu)
            {
               HelperControl.instance.checkHelper();
               HelperMenuControl.instance.menuClosed(HelperMainMenu.NPC);
            }
            else if(_loc2_ is StoreBuyMenu || _loc2_ is StoreSellMenu)
            {
               HelperMenuControl.instance.menuClosed(HelperMainMenu.STORE);
            }
            else if(_loc2_ is MapPanel)
            {
               HelperMenuControl.instance.menuClosed(HelperMainMenu.MAP);
            }
            if(param1 == null || param1 == menu)
            {
               menu = null;
            }
            trackMobileMotion(_loc2_,false);
            TweenMax.to(_loc2_,DURATION,{
               "y":-_loc2_.height - HIDE_POSITION,
               "ease":Linear.easeIn,
               "bezier":[{"y":DROP_EXTENSION}],
               "onComplete":SetInvisible,
               "onCompleteParams":[_loc2_]
            });
         }
      }
      
      public static function ShowMenu(param1:Sprite) : *
      {
         var menuToShow:Sprite = param1;
         try
         {
            if(menu.iamtrade)
            {
               if(!(menuToShow is ChangeActivationMenu))
               {
                  menu.checkClose();
               }
               return;
            }
         }
         catch(e:*)
         {
         }
         SetInvisible(menu);
         menuToShow.y = -menuToShow.height - HIDE_POSITION;
         menuToShow.x = 480 - int(menuToShow.width / 2);
         MainGetter.MainCaller.getUILayer().placeMenu(menuToShow);
         menuToShow.visible = true;
         menuToShow.filters = SHADOW_FILTER;
         trackMobileMotion(menuToShow,true);
         TweenMax.to(menuToShow,DURATION,{
            "y":0,
            "ease":Linear.easeIn,
            "bezier":[{"y":DROP_EXTENSION}]
         });
         menu = menuToShow;
         if(menuToShow is CreditsStorePane)
         {
            MainGetter.MainCaller.uiLayer.setChatVisible(false);
            if((menuToShow as CreditsStorePane).store)
            {
               (menuToShow as CreditsStorePane).store.onShow();
               MainGetter.MainCaller.SetInCreditsStoreVariable(true);
            }
            menuToShow.x = 10;
         }
         else if(menuToShow is NPCDataMenu || menuToShow is QuestMenu)
         {
            HelperQuests.instance.recheckQuestHelpButtons();
         }
      }
      
      public static function ImmidiateShowMenu(param1:Sprite, param2:Boolean = false) : *
      {
         var menuToShow:Sprite = param1;
         var ingoreWidth:Boolean = param2;
         clearMobileMotion(menuToShow);
         try
         {
            if(menu.iamtrade)
            {
               menu.checkClose();
               return;
            }
         }
         catch(e:*)
         {
         }
         SetInvisible(menu);
         if(!ingoreWidth)
         {
            menuToShow.x = 480 - int(menuToShow.width / 2);
         }
         MainGetter.MainCaller.getUILayer().placeMenu(menuToShow);
         menuToShow.visible = true;
         menuToShow.filters = SHADOW_FILTER;
         menu = menuToShow;
         if(menuToShow is CreditsStorePane)
         {
            MainGetter.MainCaller.uiLayer.setChatVisible(false);
            if((menuToShow as CreditsStorePane).store)
            {
               (menuToShow as CreditsStorePane).store.onShow();
               MainGetter.MainCaller.SetInCreditsStoreVariable(false);
            }
            menuToShow.x = 10;
         }
         else if(menuToShow is NPCDataMenu || menuToShow is QuestMenu)
         {
            HelperQuests.instance.recheckQuestHelpButtons();
         }
      }
      
      public static function SetInvisible(param1:*) : *
      {
         var menuTohide:* = param1;
         if(menuTohide != null && menuTohide.visible != false)
         {
            clearMobileMotion(menuTohide);
            menuTohide.visible = false;
            if(menuTohide.parent)
            {
               menuTohide.parent.removeChild(menuTohide);
            }
            if(menuTohide is ShowHideMenu)
            {
               MainMenu.SetState((menuTohide as ShowHideMenu).menuID,false,false);
            }
            try
            {
               if(menuTohide.iamtrade)
               {
                  menuTohide.invelidateTarnsaction();
               }
            }
            catch(e:*)
            {
            }
            try
            {
               if(menuTohide.hideOp)
               {
                  menuTohide.hideOp();
               }
            }
            catch(e:*)
            {
            }
            if(menuTohide is CreditsStorePane)
            {
               MainGetter.MainCaller.uiLayer.setChatVisible(true);
               MainGetter.MainCaller.SetInCreditsStoreVariable(false);
            }
            else if(menuTohide is NPCDataMenu)
            {
               HelperControl.instance.checkHelper();
               HelperMenuControl.instance.menuClosed(HelperMainMenu.NPC);
            }
            else if(menuTohide is StoreBuyMenu || menuTohide is StoreSellMenu)
            {
               HelperMenuControl.instance.menuClosed(HelperMainMenu.STORE);
            }
            else if(menuTohide is MapPanel)
            {
               HelperMenuControl.instance.menuClosed(HelperMainMenu.MAP);
            }
         }
      }
      
      public static function ImmidiateHide(param1:*) : *
      {
         var menuTohide:* = param1;
         if(menuTohide != null)
         {
            if(menuTohide.parent)
            {
               menuTohide.parent.removeChild(menuTohide);
            }
            clearMobileMotion(menuTohide);
            menuTohide.visible = false;
            menuTohide.y = -100 - menuTohide.height;
            if(menuTohide is ShowHideMenu)
            {
               MainMenu.SetState((menuTohide as ShowHideMenu).menuID,false);
            }
            if(menuTohide == menu)
            {
               menu = null;
            }
            try
            {
               if(menuTohide.iamtrade)
               {
                  menuTohide.invelidateTarnsaction();
               }
            }
            catch(e:*)
            {
            }
            try
            {
               if(menuTohide.hideOp)
               {
                  menuTohide.hideOp();
               }
            }
            catch(e:*)
            {
            }
            if(menuTohide is CreditsStorePane)
            {
               MainGetter.MainCaller.uiLayer.setChatVisible(true);
               MainGetter.MainCaller.SetInCreditsStoreVariable(false);
            }
            else if(menuTohide is NPCDataMenu)
            {
               HelperControl.instance.checkHelper();
               HelperMenuControl.instance.menuClosed(HelperMainMenu.NPC);
            }
            else if(menuTohide is StoreBuyMenu || menuTohide is StoreSellMenu)
            {
               HelperMenuControl.instance.menuClosed(HelperMainMenu.STORE);
            }
            else if(menuTohide is MapPanel)
            {
               HelperMenuControl.instance.menuClosed(HelperMainMenu.MAP);
            }
         }
      }
      
      public static function get CurrentMenu() : *
      {
         return menu;
      }
   }
}

