import { api, track, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import getChannels from '@salesforce/apex/MaxDootChannelController.getChannels';
import startConversation from '@salesforce/apex/MaxDootSendController.startConversation';
import searchMyRecipients from '@salesforce/apex/MaxDootSendController.searchMyRecipients';

/**
 * Compose modal for proactive outbound WhatsApp messages.
 * Opened from the inbox "New Message" button or a Contact/Lead record-page button.
 *
 * From the inbox the agent searches THEIR OWN contacts/leads (ownership enforced
 * server-side) and picks a recipient — they cannot message someone else's customer.
 * When opened from a record page the recipient is prefilled, so the picker is hidden.
 */
export default class MaxdootCompose extends LightningModal {
    @api toNumber = '';
    @api recipientName = '';
    @api contactId = null;
    @api leadId = null;
    @api channelId = null;

    @track channelOptions = [];
    @track results = [];
    searchTerm = '';
    searching = false;
    picked = false;
    _prefilled = false;
    _debounce;

    draft = '';
    sending = false;
    errorMessage = '';

    connectedCallback() {
        // Captured once: opened from a record page (recipient already known).
        this._prefilled = !!(this.contactId || this.leadId || this.toNumber);
    }

    @wire(getChannels)
    wiredChannels({ data }) {
        if (data) {
            this.channelOptions = data.map((c) => ({
                label: c.Session_Status__c ? `${c.Name} (${c.Session_Status__c})` : c.Name,
                value: c.Id
            }));
            if (!this.channelId && this.channelOptions.length === 1) {
                this.channelId = this.channelOptions[0].value;
            }
        }
    }

    get hasChannels() {
        return this.channelOptions.length > 0;
    }
    get heading() {
        return this.recipientName ? `New WhatsApp message to ${this.recipientName}` : 'New WhatsApp message';
    }
    get showPicker() {
        return !this._prefilled && !this.picked;
    }
    get showSelected() {
        return this._prefilled || this.picked;
    }
    get canChange() {
        return this.picked; // only the inbox flow allows re-picking
    }
    get hasResults() {
        return this.results && this.results.length > 0;
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
    handleDraft(event) {
        this.draft = event.target.value;
    }

    handleRecipientSearch(event) {
        const term = event.target.value;
        this.searchTerm = term;
        if (this._debounce) clearTimeout(this._debounce);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounce = setTimeout(() => this.runSearch(term), 250);
    }

    async runSearch(term) {
        if (!term || term.trim().length < 2) {
            this.results = [];
            return;
        }
        this.searching = true;
        try {
            const data = await searchMyRecipients({ term });
            this.results = data || [];
        } catch (e) {
            this.results = [];
        } finally {
            this.searching = false;
        }
    }

    handlePick(event) {
        const id = event.currentTarget.dataset.id;
        const r = this.results.find((x) => x.recordId === id);
        if (!r) return;
        this.toNumber = r.phone;
        this.recipientName = r.name;
        this.contactId = r.type === 'Contact' ? r.recordId : null;
        this.leadId = r.type === 'Lead' ? r.recordId : null;
        this.picked = true;
        this.results = [];
        this.searchTerm = '';
    }

    handleChangeRecipient() {
        this.picked = false;
        this.contactId = null;
        this.leadId = null;
        this.toNumber = '';
        this.recipientName = '';
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
                (error && error.body && error.body.message) || 'Could not send the message.';
        } finally {
            this.sending = false;
        }
    }
}
