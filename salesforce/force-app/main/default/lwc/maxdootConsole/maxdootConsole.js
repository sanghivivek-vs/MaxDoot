import { LightningElement, track } from 'lwc';

export default class MaxdootConsole extends LightningElement {
    @track selectedConversationId;

    handleSelect(event) {
        this.selectedConversationId = event.detail.conversationId;
    }
}
