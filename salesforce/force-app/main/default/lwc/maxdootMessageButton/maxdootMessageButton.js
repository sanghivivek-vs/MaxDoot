import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import MaxdootCompose from 'c/maxdootCompose';

/**
 * "Message on WhatsApp" button for a Contact or Lead record page.
 * Reads the record's name + phone and opens the compose modal pre-filled,
 * linking the new conversation back to this Contact/Lead.
 */
export default class MaxdootMessageButton extends LightningElement {
    @api recordId;
    @api objectApiName;

    name;
    mobilePhone;
    phone;

    get fieldList() {
        if (!this.objectApiName) return [];
        return [
            `${this.objectApiName}.Name`,
            `${this.objectApiName}.Phone`,
            `${this.objectApiName}.MobilePhone`
        ];
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$fieldList' })
    wiredRecord({ data }) {
        if (data) {
            this.name = getFieldValue(data, `${this.objectApiName}.Name`);
            this.mobilePhone = getFieldValue(data, `${this.objectApiName}.MobilePhone`);
            this.phone = getFieldValue(data, `${this.objectApiName}.Phone`);
        }
    }

    get recipientNumber() {
        return this.mobilePhone || this.phone || '';
    }

    get isContact() {
        return this.objectApiName === 'Contact';
    }

    async handleClick() {
        const conversationId = await MaxdootCompose.open({
            size: 'small',
            description: 'Start a new WhatsApp conversation',
            toNumber: this.recipientNumber,
            recipientName: this.name,
            contactId: this.isContact ? this.recordId : null,
            leadId: this.isContact ? null : this.recordId
        });
        if (conversationId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Message sent',
                    message: 'WhatsApp conversation started in MaxDoot.',
                    variant: 'success'
                })
            );
        }
    }
}
