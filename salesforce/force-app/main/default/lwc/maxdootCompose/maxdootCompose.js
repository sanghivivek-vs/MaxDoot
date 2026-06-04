import { api, track, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import getChannels from '@salesforce/apex/MaxDootChannelController.getChannels';
import startConversation from '@salesforce/apex/MaxDootSendController.startConversation';

/**
 * Compose modal for proactive outbound WhatsApp messages.
 * Opened from the inbox "New Message" button or a Contact/Lead record-page button.
 * Prefill via the api properties; resolves with the new/!existing conversation id.
 */
export default class MaxdootCompose extends LightningModal {
    @api toNumber = '';
    @api recipientName = '';
    @api contactId = null;
    @api leadId = null;
    @api channelId = null;

    @track channelOptions = [];
    draft = '';
    sending = false;
    errorMessage = '';

    @wire(getChannels)
    wiredChannels({ data }) {
        if (data) {
            this.channelOptions = data.map((c) => ({
                label: c.Session_Status__c
                    ? `${c.Name} (${c.Session_Status__c})`
                    : c.Name,
                value: c.Id
            }));
            // Default to the only channel, or keep any prefilled selection.
            if (!this.channelId && this.channelOptions.length === 1) {
                this.channelId = this.channelOptions[0].value;
            }
        }
    }

    get hasChannels() {
        return this.channelOptions.length > 0;
    }

    get heading() {
        return this.recipientName
            ? `New WhatsApp message to ${this.recipientName}`
            : 'New WhatsApp message';
    }

    get sendDisabled() {
        return (
            this.sending ||
            !this.channelId ||
            !this.toNumber ||
            !this.draft ||
            !this.draft.trim()
        );
    }

    handleChannel(event) {
        this.channelId = event.detail.value;
    }

    handleNumber(event) {
        this.toNumber = event.target.value;
    }

    handleDraft(event) {
        this.draft = event.target.value;
    }

    handleCancel() {
        this.close(null);
    }

    async handleSend() {
        const body = this.draft.trim();
        if (this.sendDisabled) return;
        this.sending = true;
        this.errorMessage = '';
        try {
            const conversationId = await startConversation({
                channelId: this.channelId,
                toNumber: this.toNumber,
                contactId: this.contactId,
                leadId: this.leadId,
                body,
                mediaUrl: null
            });
            this.close(conversationId);
        } catch (error) {
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Could not send the message.';
        } finally {
            this.sending = false;
        }
    }
}
