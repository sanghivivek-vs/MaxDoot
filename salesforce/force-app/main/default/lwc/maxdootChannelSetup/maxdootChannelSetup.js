import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChannels from '@salesforce/apex/MaxDootChannelController.getChannels';
import getQr from '@salesforce/apex/MaxDootChannelController.getQr';
import refreshStatus from '@salesforce/apex/MaxDootChannelController.refreshStatus';

export default class MaxdootChannelSetup extends LightningElement {
    @track channels = [];
    @track selectedId;
    @track qrValue;
    @track statusLabel = '';
    loading = true;
    qrLoading = false;
    _wireResult;

    @wire(getChannels)
    wired(result) {
        this._wireResult = result;
        if (result.data) {
            this.channels = result.data.map((c) => this.decorate(c));
            this.loading = false;
            const sel = this.channels.find((c) => c.Id === this.selectedId);
            if (sel) this.statusLabel = sel.Session_Status__c;
        } else if (result.error) {
            this.loading = false;
        }
    }

    decorate(c) {
        const selected = c.Id === this.selectedId;
        const badge =
            c.Session_Status__c === 'Connected'
                ? 'slds-theme_success'
                : c.Session_Status__c === 'Disconnected'
                ? 'slds-theme_error'
                : 'slds-theme_warning';
        return {
            ...c,
            cssClass: 'slds-item maxdoot-channel-item' + (selected ? ' maxdoot-channel-selected' : ''),
            badgeClass: badge
        };
    }

    get selectedChannel() {
        return this.channels.find((c) => c.Id === this.selectedId);
    }
    get noSelection() {
        return !this.selectedId;
    }
    get noChannels() {
        return !this.loading && this.channels.length === 0;
    }
    get qrIsImage() {
        return this.qrValue && (this.qrValue.startsWith('data:image') || this.qrValue.startsWith('http'));
    }
    get qrIsText() {
        return this.qrValue && !this.qrIsImage;
    }

    handleSelect(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.qrValue = null;
        const sel = this.selectedChannel;
        this.statusLabel = sel ? sel.Session_Status__c : '';
        this.channels = this.channels.map((c) => this.decorate(c));
    }

    async handleLoadQr() {
        this.qrLoading = true;
        this.qrValue = null;
        try {
            this.qrValue = await getQr({ channelId: this.selectedId });
        } catch (error) {
            this.toast('Could not load QR', this.errMsg(error), 'error');
        } finally {
            this.qrLoading = false;
        }
    }

    async handleRefreshStatus() {
        try {
            this.statusLabel = await refreshStatus({ channelId: this.selectedId });
            await refreshApex(this._wireResult);
        } catch (error) {
            this.toast('Could not refresh status', this.errMsg(error), 'error');
        }
    }

    errMsg(error) {
        return (error && error.body && error.body.message) || 'Unknown error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
