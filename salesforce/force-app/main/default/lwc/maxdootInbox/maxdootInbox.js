import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getOpenConversations from '@salesforce/apex/MaxDootSendController.getOpenConversations';
import MaxdootCompose from 'c/maxdootCompose';

const CHANNEL = '/event/MaxDoot_Inbound__e';

const OWNER_SCOPES = [
    { label: 'My chats', value: 'Mine' },
    { label: 'Unassigned', value: 'Unassigned' },
    { label: 'All', value: 'All' }
];

export default class MaxdootInbox extends LightningElement {
    @track searchTerm = '';
    @track selectedId;
    @track ownerScope = 'Mine';
    ownerScopes = OWNER_SCOPES;
    loading = true;
    _wireResult;
    _subscription;
    rows = [];

    @wire(getOpenConversations, { statusFilter: 'Open', ownerScope: '$ownerScope' })
    wired(result) {
        this._wireResult = result;
        if (result.data) {
            this.rows = result.data.map((c) => this.decorate(c));
            this.loading = false;
        } else if (result.error) {
            this.loading = false;
        }
    }

    async connectedCallback() {
        onError((err) => {
            // eslint-disable-next-line no-console
            console.error('MaxDoot empApi error', JSON.stringify(err));
        });
        try {
            this._subscription = await subscribe(CHANNEL, -1, () => this.refresh());
        } catch (e) {
            // empApi may be unavailable in some contexts; inbox still works via manual refresh.
        }
    }

    disconnectedCallback() {
        if (this._subscription) {
            unsubscribe(this._subscription, () => {});
        }
    }

    refresh() {
        return refreshApex(this._wireResult);
    }

    decorate(c) {
        const name =
            (c.Is_Group__c && (c.Group_Name__c || 'Group chat')) ||
            (c.Contact__r && c.Contact__r.Name) ||
            (c.Lead__r && c.Lead__r.Name) ||
            c.Customer_Number__c ||
            c.Name;
        const unread = c.Unread_Count__c > 0;
        return {
            ...c,
            displayName: name,
            initials: this.initialsOf(name),
            hasUnread: unread,
            relativeTime: this.formatTime(c.Last_Inbound__c),
            cssClass:
                'slds-item maxdoot-conv-item' +
                (c.Id === this.selectedId ? ' maxdoot-conv-selected' : '')
        };
    }

    initialsOf(name) {
        if (!name) return '?';
        const parts = String(name).trim().split(/\s+/);
        let s = parts[0].charAt(0);
        if (parts.length > 1) s += parts[parts.length - 1].charAt(0);
        return s.toUpperCase();
    }

    formatTime(value) {
        if (!value) return '';
        const d = new Date(value);
        return d.toLocaleString(undefined, { hour: '2-digit', minute: '2-digit' });
    }

    get filtered() {
        const term = this.searchTerm.toLowerCase();
        const list = term
            ? this.rows.filter(
                  (r) =>
                      (r.displayName || '').toLowerCase().includes(term) ||
                      (r.Last_Message_Preview__c || '').toLowerCase().includes(term)
              )
            : this.rows;
        return list.map((r) => ({
            ...r,
            cssClass:
                'slds-item maxdoot-conv-item' +
                (r.Id === this.selectedId ? ' maxdoot-conv-selected' : '')
        }));
    }

    get isEmpty() {
        return !this.loading && this.filtered.length === 0;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleScope(event) {
        const value = event.target && event.target.value;
        if (value && value !== this.ownerScope) {
            this.ownerScope = value;
        }
    }

    handleClick(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.dispatchEvent(
            new CustomEvent('select', { detail: { conversationId: this.selectedId } })
        );
    }

    async handleNew() {
        const conversationId = await MaxdootCompose.open({
            size: 'small',
            description: 'Start a new WhatsApp conversation'
        });
        if (conversationId) {
            await this.refresh();
            this.selectedId = conversationId;
            this.dispatchEvent(
                new CustomEvent('select', { detail: { conversationId } })
            );
        }
    }
}
