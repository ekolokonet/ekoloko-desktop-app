package {
    /** One focus assignment per explicit open, whether COMPLETE is sync or async. */
    public final class MobileInputFocus {
        private var pending:Boolean=false,ready:Boolean=false,opening:Boolean=false;
        public function begin(alreadyAttached:Boolean=false):void {pending=true;ready=alreadyAttached;opening=true;}
        public function complete():Boolean {ready=true;return take();}
        public function commit():Boolean {opening=false;return take();}
        public function close():void {pending=ready=opening=false;}
        private function take():Boolean {
            if(!pending||!ready||opening)return false;
            pending=false;return true;
        }
    }
}
