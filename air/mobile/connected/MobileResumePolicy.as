package {
    /** Short interruptions preserve a live session. Suspended sessions restart
     * through the native host because a socket's connected flag can be stale. */
    public final class MobileResumePolicy {
        public static function restart(elapsed:Number, hadSession:Boolean, connected:Boolean, wasLoading:Boolean):Boolean {
            return (hadSession && (!connected || elapsed >= 30000)) || (wasLoading && elapsed >= 30000);
        }
    }
}
