package com.paperglide.app

/** Set before launch from instrumentation. A normal launch leaves every flag false. */
object DebugLaunch {
    @Volatile var resetStore: Boolean = false
    @Volatile var worstCaseDeath: Boolean = false
    @Volatile var endScore: Int? = null
    @Volatile var seed: Long? = null
    @Volatile var guidedStride: Double? = null
    @Volatile var forceShareFail: Boolean = false
    @Volatile var offline: Boolean = false
    /** "ok", "offline", or "fail". Null uses the real backend. */
    @Volatile var fakeDelete: String? = null

    fun clear() {
        resetStore = false
        worstCaseDeath = false
        endScore = null
        seed = null
        guidedStride = null
        forceShareFail = false
        offline = false
        fakeDelete = null
    }
}
