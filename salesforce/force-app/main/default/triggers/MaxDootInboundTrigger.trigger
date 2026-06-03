/**
 * Fires on the MaxDoot_Inbound__e platform event. Delegates all work to the handler.
 * The same event stream is also consumed by the LWC layer via lightning/empApi for
 * live UI updates, so this trigger is purely for persistence.
 */
trigger MaxDootInboundTrigger on MaxDoot_Inbound__e (after insert) {
    MaxDootInboundHandler.handle(Trigger.new);
}
