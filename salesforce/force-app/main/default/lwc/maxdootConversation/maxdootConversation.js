import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe } from 'lightning/empApi';
import getMessages from '@salesforce/apex/MaxDootSendController.getMessages';
import sendMessage from '@salesforce/apex/MaxDootSendController.sendMessage';
import markRead from '@salesforce/apex/MaxDootSendController.markRead';
import uploadAttachment from '@salesforce/apex/MaxDootSendController.uploadAttachment';
import getConversationHeader from '@salesforce/apex/MaxDootSendController.getConversationHeader';

const CHANNEL = '/event/MaxDoot_Inbound__e';
const MAX_FILE_BYTES = 5 * 1024 * 1024; // 5 MB — keeps the base64 payload within Apex request limits
const EMOJIS = [
    '😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤩', '🥳',
    '🙂', '😉', '🤔', '😢', '😭', '😡', '😱', '🙏', '👍', '👎',
    '👏', '🙌', '🤝', '💪', '🔥', '✨', '🎉', '❤️', '💯', '✅',
    '❌', '⚠️', '📌', '📎', '📞', '💬', '🕒', '💰', '🎓', '🚀'
];

export default class MaxdootConversation extends LightningElement {
    _conversationId;
    @track messages = [];
    @track draft = '';
    loading = false;
    sending = false;
    windowClosed = false;
    _wireResult;
    _subscription;

    // Composer extras
    showEmoji = false;
    uploading = false;
    pendingMediaUrl = null;
    pendingFileName = null;

    // Message ids whose media failed to render as an image (fall back to a link).
    _failedImages = new Set();

    @api
    get conversationId() {
        return this._conversationId;
    }
    set conversationId(value) {
        this._conversationId = value;
        this.draft = '';
        this.clearAttachment();
        this.showEmoji = false;
        if (value) {
            this.loading = true;
            markRead({ conversationId: value }).catch(() => {});
        }
    }

    @track header;
    @wire(getConversationHeader, { conversationId: '$_conversationId' })
    wiredHeader({ data }) {
        if (data) {
            const name = data.Is_Group__c
                ? data.Group_Name__c || 'Group'
                : (data.Contact__r && data.Contact__r.Name) ||
                  (data.Lead__r && data.Lead__r.Name) ||
                  data.Customer_Number__c ||
                  'Unknown';
            const sub = data.Is_Group__c
                ? 'Group chat'
                : data.Customer_Number__c || '';
            this.header = {
                name,
                sub,
                initials: this.initialsOf(name),
                channel: data.Channel__r && data.Channel__r.Name
            };
        } else {
            this.header = null;
        }
    }

    initialsOf(name) {
        if (!name) return '?';
        const parts = String(name).trim().split(/\s+/);
        let s = parts[0].charAt(0);
        if (parts.length > 1) s += parts[parts.length - 1].charAt(0);
        return s.toUpperCase();
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
        // Optimistically render any media as an image thumbnail; the <img> onerror
        // falls back to a plain link for non-images (PDF, docs, etc.). This avoids a
        // schema change and works for both inbound and uploaded media URLs.
        const hasMedia = !!m.Media_URL__c;
        const failed = this._failedImages.has(m.Id);
        return {
            ...m,
            isOutbound: outbound,
            senderLabel: !outbound && m.Sender_Name__c ? m.Sender_Name__c : null,
            showThumb: hasMedia && !failed,
            showLink: hasMedia && failed,
            rowClass: 'slds-grid ' + (outbound ? 'slds-grid_align-end' : 'slds-grid_align-start'),
            bubbleClass:
                'maxdoot-bubble ' + (outbound ? 'maxdoot-bubble-out' : 'maxdoot-bubble-in'),
            timeLabel: ts
                ? new Date(ts).toLocaleString(undefined, { hour: '2-digit', minute: '2-digit' })
                : ''
        };
    }

    handleImgError(event) {
        const id = event.target.dataset.id;
        if (!id || this._failedImages.has(id)) return;
        this._failedImages.add(id);
        this.messages = this.messages.map((x) =>
            x.Id === id ? { ...x, showThumb: false, showLink: true } : x
        );
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
    get emojis() {
        return EMOJIS;
    }
    get hasAttachment() {
        return !!this.pendingMediaUrl;
    }
    get sendDisabled() {
        const hasText = this.draft && this.draft.trim();
        return this.sending || this.uploading || (!hasText && !this.pendingMediaUrl);
    }

    handleDraft(event) {
        this.draft = event.target.value;
    }

    // ---- emoji ----------------------------------------------------------------
    toggleEmoji() {
        this.showEmoji = !this.showEmoji;
    }

    handleEmoji(event) {
        const emoji = event.currentTarget.dataset.emoji;
        this.draft = (this.draft || '') + emoji;
        this.showEmoji = false;
        // return focus to the textarea
        const ta = this.template.querySelector('lightning-textarea');
        if (ta) ta.focus();
    }

    // ---- attachment -----------------------------------------------------------
    handleAttachClick() {
        const input = this.template.querySelector('input[type="file"]');
        if (input) input.click();
    }

    async handleFileChange(event) {
        const file = event.target.files && event.target.files[0];
        // reset so the same file can be re-selected later
        event.target.value = null;
        if (!file) return;
        if (file.size > MAX_FILE_BYTES) {
            this.toast('File too large', 'Attachments must be 5 MB or smaller.', 'error');
            return;
        }
        this.uploading = true;
        try {
            const base64 = await this.readAsBase64(file);
            const url = await uploadAttachment({
                conversationId: this._conversationId,
                fileName: file.name,
                base64Data: base64
            });
            this.pendingMediaUrl = url;
            this.pendingFileName = file.name;
        } catch (error) {
            this.toast('Attachment failed', this.errMsg(error), 'error');
        } finally {
            this.uploading = false;
        }
    }

    readAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    clearAttachment() {
        this.pendingMediaUrl = null;
        this.pendingFileName = null;
    }

    removeAttachment() {
        this.clearAttachment();
    }

    // ---- send -----------------------------------------------------------------
    async handleSend() {
        const body = (this.draft || '').trim();
        const mediaUrl = this.pendingMediaUrl;
        if (!body && !mediaUrl) return;
        this.sending = true;
        try {
            await sendMessage({ conversationId: this._conversationId, body, mediaUrl });
            this.draft = '';
            this.clearAttachment();
            await refreshApex(this._wireResult);
            this.scrollToBottom();
        } catch (error) {
            this.toast('Send failed', this.errMsg(error), 'error');
        } finally {
            this.sending = false;
        }
    }

    errMsg(error) {
        return (error && error.body && error.body.message) || 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const thread = this.template.querySelector('.maxdoot-thread');
            if (thread) thread.scrollTop = thread.scrollHeight;
        }, 50);
    }
}
