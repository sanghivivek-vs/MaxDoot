import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe } from 'lightning/empApi';
import getMessages from '@salesforce/apex/MaxDootSendController.getMessages';
import sendMessage from '@salesforce/apex/MaxDootSendController.sendMessage';
import markRead from '@salesforce/apex/MaxDootSendController.markRead';

const CHANNEL = '/event/MaxDoot_Inbound__e';

export default class MaxdootConversation extends LightningElement {
    _conversationId;
    @track messages = [];
    @track draft = '';
    loading = false;
    sending = false;
    windowClosed = false;
    _wireResult;
    _subscription;

    @api
    get conversationId() {
        return this._conversationId;
    }
    set conversationId(value) {
        this._conversationId = value;
        this.draft = '';
        if (value) {
            this.loading = true;
            markRead({ conversationId: value }).catch(() => {});
        }
    }

    @wire(getMessages, { conversationId: '$_conversationId' })
    wired(result) {
        this._wireResult = result;
        if (result.data) {
            this.messages = result.data.map((m) => this.decorate(m));
            this.loading = false;
            this.scrollToBottom();
        } else if (result.error) {
            this.loading = false;
        }
    }

    async connectedCallback() {
        try {
            this._subscription = await subscribe(CHANNEL, -1, () => {
                if (this._conversationId) refreshApex(this._wireResult);
            });
        } catch (e) {
            // empApi optional
        }
    }

    disconnectedCallback() {
        if (this._subscription) {
            unsubscribe(this._subscription, () => {});
        }
    }

    decorate(m) {
        const outbound = m.Direction__c === 'Outbound';
        const ts = m.Timestamp__c || m.CreatedDate;
        return {
            ...m,
            isOutbound: outbound,
            rowClass: 'slds-grid ' + (outbound ? 'slds-grid_align-end' : 'slds-grid_align-start'),
            bubbleClass:
                'maxdoot-bubble ' + (outbound ? 'maxdoot-bubble-out' : 'maxdoot-bubble-in'),
            timeLabel: ts
                ? new Date(ts).toLocaleString(undefined, { hour: '2-digit', minute: '2-digit' })
                : ''
        };
    }

    get hasConversation() {
        return !!this._conversationId;
    }
    get noConversation() {
        return !this._conversationId;
    }
    get isEmpty() {
        return !this.loading && this.messages.length === 0;
    }
    get sendDisabled() {
        return this.sending || !this.draft || !this.draft.trim();
    }

    handleDraft(event) {
        this.draft = event.target.value;
    }

    async handleSend() {
        const body = this.draft.trim();
        if (!body) return;
        this.sending = true;
        try {
            await sendMessage({ conversationId: this._conversationId, body, mediaUrl: null });
            this.draft = '';
            await refreshApex(this._wireResult);
            this.scrollToBottom();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Send failed',
                    message: (error && error.body && error.body.message) || 'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.sending = false;
        }
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const thread = this.template.querySelector('.maxdoot-thread');
            if (thread) thread.scrollTop = thread.scrollHeight;
        }, 50);
    }
}
