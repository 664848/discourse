# frozen_string_literal: true

RSpec.describe "JIT messages", type: :system, js: true do
  fab!(:channel_1) { Fabricate(:chat_channel) }
  fab!(:current_user) { Fabricate(:user) }
  fab!(:other_user) { Fabricate(:user) }

  let(:chat) { PageObjects::Pages::Chat.new }

  before do
    channel_1.add(current_user)
    chat_system_bootstrap
    sign_in(current_user)
  end

  context "when mentioning a user not on the channel" do
    it "displays a mention warning" do
      chat.visit_channel(channel_1)
      find(".chat-composer-input").fill_in(with: "hi @#{other_user.username}")
      find(".send-btn").click

      expect(page).to have_content(
        I18n.t("js.chat.mention_warning.without_membership.one", username: other_user.username),
      )
    end
  end

  context "when mentioning a user who can’t access the channel" do
    fab!(:group_1) { Fabricate(:group) }
    fab!(:private_channel_1) { Fabricate(:private_category_channel, group: group_1) }

    before do
      group_1.add(current_user)
      private_channel_1.add(current_user)
    end

    it "displays a mention warning" do
      chat.visit_channel(private_channel_1)
      find(".chat-composer-input").fill_in(with: "hi @#{other_user.username}")
      find(".chat-composer-input").click
      find(".send-btn").click

      expect(page).to have_content(
        I18n.t("js.chat.mention_warning.cannot_see.one", username: other_user.username),
      )
    end
  end

  context "when mention a group" do
    context "when group can't be mentioned" do
      fab!(:group_1) { Fabricate(:group, mentionable_level: Group::ALIAS_LEVELS[:nobody]) }

      it "displays a mention warning" do
        chat.visit_channel(channel_1)
        find(".chat-composer-input").fill_in(with: "hi @#{group_1.name}")
        find(".send-btn").click

        expect(page).to have_content(
          I18n.t("js.chat.mention_warning.group_mentions_disabled.one", group_name: group_1.name),
        )
      end
    end
  end
end
