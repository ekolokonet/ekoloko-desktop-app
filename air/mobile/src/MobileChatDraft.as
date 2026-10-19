package {
    /** Draft lives outside StageText: native focus/detach can return an empty value. */
    public final class MobileChatDraft {
        private var value:String="";
        public function get text():String {return value;}
        public function accept(text:String):void {value=text.replace(/[\u200e\u200f]/g,"");}
        public function readNative(text:String,userChange:Boolean=false):void {
            // An explicit CHANGE can delete all characters. An empty teardown
            // snapshot cannot erase a previously observed nonempty draft.
            if(userChange||text.length>0||value.length==0)accept(text);
        }
    }
}
