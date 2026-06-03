import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getStats from '@salesforce/apex/MaxDootDashboardController.getStats';

export default class MaxdootDashboard extends LightningElement {
    @track cards = [];
    loading = true;
    _wireResult;

    @wire(getStats)
    wired(result) {
        this._wireResult = result;
        if (result.data) {
            const s = result.data;
            this.cards = [
                { label: 'Open', value: s.openConversations },
                { label: 'Unassigned', value: s.unassigned },
                { label: 'Unread', value: s.unread },
                { label: 'Messages Today', value: s.messagesToday },
                { label: 'Channels Online', value: s.connectedChannels }
            ];
            this.loading = false;
        } else if (result.error) {
            this.loading = false;
        }
    }

    handleRefresh() {
        refreshApex(this._wireResult);
    }
}
