import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConversationIdForRecord from '@salesforce/apex/MaxDootSendController.getConversationIdForRecord';
import MaxdootCompose from 'c/maxdootCompose';

/**
 * Embeds the WhatsApp conversation thread on a record page (Opportunity, Contact, Lead).
 * Reads the record's phone number, resolves the matching MaxDoot conversation, and renders
 * the reusable <c-maxdoot-conversation> thread. When no conversation exists yet it offers a
 * "Start WhatsApp" action that opens the compose modal pre-filled for this record.
 *
 * For objects without a standard phone field (e.g. Opportunity) set the "Phone field API name"
 * design property in the Lightning App Builder to the field that holds the WhatsApp number.
 */
export default class MaxdootRecordChat extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api phoneFieldApiName;            // design attribute; required for non-standard objects
    @api cardTitle = 'WhatsApp';

    name;
    number;
    conversationId;
    loading = true;
    resolved = false;

    get fieldList() {
        if (!this.objectApiName) return [];
        const fields = [`${this.objectApiName}.Name`];
        if (this.phoneFieldApiName) {
            fields.push(`${this.objectApiName}.${this.phoneFieldApiName}`);
        } else if (this.objectApiName === 'Contact' || this.objectApiName === 'Lead') {
            fields.push(`${this.objectApiName}.MobilePhone`, `${this.objectApiName}.Phone`);
        }
        return fields;
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldList' })
    wiredRecord({ data, error }) {
        if (data) {
            this.name = getFieldValue(data, `${this.objectApiName}.Name`);
            if (this.phoneFieldApiName) {
                this.number = getFieldValue(data, `${this.objectApiName}.${this.phoneFieldApiName}`);
            } else {
                this.number =
                    getFieldValue(data, `${this.objectApiName}.MobilePhone`) ||
                    getFieldValue(data, `${this.objectApiName}.Phone`);
            }
            this.resolve();
        } else if (error) {
            this.loading = false;
            this.resolved = true;
        }
    }

    async resolve() {
        this.loading = true;
        try {
            this.conversationId = await getConversationIdForRecord({
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                phoneNumber: this.number
            });
        } catch (e) {
            this.conversationId = null;
        } finally {
            this.resolved = true;
            this.loading = false;
        }
    }

    get hasConversation() {
        return !this.loading && !!this.conversationId;
    }

    get showEmpty() {
        return this.resolved && !this.loading && !this.conversationId;
    }

    get hasNumber() {
        return !!this.number;
    }

    async handleStart() {
        const isContact = this.objectApiName === 'Contact';
        const isLead = this.objectApiName === 'Lead';
        const conversationId = await MaxdootCompose.open({
            size: 'small',
            description: 'Start a new WhatsApp conversation',
            toNumber: this.number,
            recipientName: this.name,
            contactId: isContact ? this.recordId : null,
            leadId: isLead ? this.recordId : null
        });
        if (conversationId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Message sent',
                    message: 'WhatsApp conversation started.',
                    variant: 'success'
                })
            );
            this.resolve();
        }
    }
}
