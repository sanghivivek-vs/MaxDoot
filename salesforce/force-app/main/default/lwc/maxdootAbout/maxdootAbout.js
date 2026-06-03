import { LightningElement, track, wire } from 'lwc';
import getBranding from '@salesforce/apex/MaxDootBrandingController.getBranding';

export default class MaxdootAbout extends LightningElement {
    @track branding = {};

    @wire(getBranding)
    wired({ data }) {
        if (data) {
            this.branding = data;
        }
    }

    get hasContact() {
        const b = this.branding;
        return !!(b.supportEmail || b.supportPhone || b.supportUrl);
    }

    get noContact() {
        return !this.hasContact;
    }

    get emailHref() {
        return this.branding.supportEmail ? `mailto:${this.branding.supportEmail}` : '#';
    }

    get phoneHref() {
        return this.branding.supportPhone ? `tel:${this.branding.supportPhone}` : '#';
    }
}
