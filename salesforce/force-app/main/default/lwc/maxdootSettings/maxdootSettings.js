import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/MaxDootSettingsController.getSettings';
import updateBranding from '@salesforce/apex/MaxDootSettingsController.updateBranding';
import updateConnection from '@salesforce/apex/MaxDootSettingsController.updateConnection';
import regenerateInboundToken from '@salesforce/apex/MaxDootSettingsController.regenerateInboundToken';
import saveChannel from '@salesforce/apex/MaxDootSettingsController.saveChannel';
import refreshChannelStatus from '@salesforce/apex/MaxDootSettingsController.refreshChannelStatus';

const SCOPE_OPTIONS = [
    { label: 'Org (any agent)', value: 'Org' },
    { label: 'Team', value: 'Team' },
    { label: 'Agent', value: 'Agent' }
];

export default class MaxdootSettings extends LightningElement {
    @track s = {};
    @track channels = [];
    @track channelForm = null; // null = hidden; object = editing/adding
    loading = true;
    scopeOptions = SCOPE_OPTIONS;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const data = await getSettings();
            this.s = { ...data };
            this.channels = (data.channels || []).map((c) => this.decorate(c));
        } catch (e) {
            this.toast('Error', this.msg(e), 'error');
        } finally {
            this.loading = false;
        }
    }

    decorate(c) {
        const status = c.sessionStatus || 'Unknown';
        const theme =
            status === 'Connected'
                ? 'slds-theme_success'
                : status === 'NeedsScan'
                ? 'slds-theme_warning'
                : 'slds-theme_error';
        return { ...c, statusClass: `slds-badge ${theme}`, statusLabel: status };
    }

    // ---- Inbound webhook ----
    get hasWebhookUrl() {
        return !!this.s.webhookUrl;
    }
    get hasToken() {
        return !!this.s.inboundToken;
    }

    copy(event) {
        const value = event.currentTarget.dataset.value;
        if (value && navigator.clipboard) {
            navigator.clipboard.writeText(value);
            this.toast('Copied', 'Copied to clipboard.', 'success');
        }
    }

    async handleRegenerate() {
        // eslint-disable-next-line no-alert
        try {
            const token = await regenerateInboundToken();
            this.s = { ...this.s, inboundToken: token };
            this.toast(
                'New token generated',
                'Update heydoot with the new token. Applying (a few seconds)…',
                'success'
            );
        } catch (e) {
            this.toast('Error', this.msg(e), 'error');
        }
    }

    // ---- Connection ----
    handleField(event) {
        this.s = { ...this.s, [event.target.name]: event.target.value };
    }

    async handleSaveConnection() {
        try {
            await updateConnection({ sendPath: this.s.sendPath, statusPath: this.s.statusPath });
            this.toast('Saved', 'Connection paths applying (a few seconds)…', 'success');
        } catch (e) {
            this.toast('Error', this.msg(e), 'error');
        }
    }

    async handleSaveBranding() {
        try {
            await updateBranding({
                companyName: this.s.companyName,
                tagline: this.s.tagline,
                supportEmail: this.s.supportEmail,
                supportPhone: this.s.supportPhone,
                supportUrl: this.s.supportUrl
            });
            this.toast('Saved', 'Branding applying (a few seconds)…', 'success');
        } catch (e) {
            this.toast('Error', this.msg(e), 'error');
        }
    }

    // ---- Channels ----
    handleNewChannel() {
        this.channelForm = {
            id: null,
            name: '',
            whatsAppNumber: '',
            heydootSessionId: '',
            scope: 'Org',
            active: true,
            bearerToken: ''
        };
    }

    handleEditChannel(event) {
        const id = event.currentTarget.dataset.id;
        const c = this.channels.find((x) => x.id === id);
        this.channelForm = { ...c, bearerToken: '' };
    }

    handleFormField(event) {
        const { name, type } = event.target;
        const value = type === 'checkbox' ? event.target.checked : event.target.value;
        this.channelForm = { ...this.channelForm, [name]: value };
    }

    handleCancelForm() {
        this.channelForm = null;
    }

    async handleSaveChannel() {
        const f = this.channelForm;
        if (!f.name) {
            this.toast('Missing name', 'Give the channel a name.', 'warning');
            return;
        }
        try {
            await saveChannel({
                channelId: f.id,
                name: f.name,
                whatsAppNumber: f.whatsAppNumber,
                heydootSessionId: f.heydootSessionId,
                scope: f.scope,
                active: f.active,
                bearerToken: f.bearerToken
            });
            this.channelForm = null;
            this.toast('Saved', 'Channel saved.', 'success');
            await this.load();
        } catch (e) {
            this.toast('Error', this.msg(e), 'error');
        }
    }

    async handleRefreshStatus(event) {
        const id = event.currentTarget.dataset.id;
        try {
            const status = await refreshChannelStatus({ channelId: id });
            this.channels = this.channels.map((c) =>
                c.id === id ? this.decorate({ ...c, sessionStatus: status }) : c
            );
        } catch (e) {
            this.toast('Status check failed', this.msg(e), 'error');
        }
    }

    get isEditing() {
        return this.channelForm && this.channelForm.id;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    msg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unknown error';
    }
}
