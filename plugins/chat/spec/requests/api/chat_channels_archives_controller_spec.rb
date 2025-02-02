# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chat::Api::ChatChannelsArchivesController do
  fab!(:user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category) { Fabricate(:category) }
  fab!(:channel) { Fabricate(:category_channel, chatable: category) }

  let(:new_topic_params) do
    {
      archive: {
        type: "new_topic",
        title: "This is a test archive topic",
        category_id: category.id,
      },
    }
  end
  let(:existing_topic_params) do
    { archive: { type: "existing_topic", topic_id: Fabricate(:topic).id } }
  end

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.chat_duplicate_message_sensitivity = 0
  end

  describe "#create" do
    it "returns error if user is not staff" do
      sign_in(user)
      post "/chat/api/channels/#{channel.id}/archives", params: new_topic_params
      expect(response.status).to eq(403)
    end

    it "returns error if type or chat_channel_id is not provided" do
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives"
      expect(response.status).to eq(400)
    end

    it "returns error if title is not provided for new topic" do
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives", params: { type: "new_topic" }
      expect(response.status).to eq(400)
    end

    it "returns error if topic_id is not provided for existing topic" do
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives", params: { type: "existing_topic" }
      expect(response.status).to eq(400)
    end

    it "returns error if the channel cannot be archived" do
      channel.update!(status: :archived)
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives", params: new_topic_params
      expect(response.status).to eq(403)
    end

    it "starts the archive process using a new topic" do
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives", params: new_topic_params
      channel_archive = ChatChannelArchive.find_by(chat_channel: channel)
      expect(
        job_enqueued?(
          job: :chat_channel_archive,
          args: {
            chat_channel_archive_id: channel_archive.id,
          },
        ),
      ).to eq(true)
      expect(channel.reload.status).to eq("read_only")
    end

    it "starts the archive process using an existing topic" do
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives", params: existing_topic_params
      channel_archive = ChatChannelArchive.find_by(chat_channel: channel)
      expect(
        job_enqueued?(
          job: :chat_channel_archive,
          args: {
            chat_channel_archive_id: channel_archive.id,
          },
        ),
      ).to eq(true)
      expect(channel.reload.status).to eq("read_only")
    end

    it "does nothing if the chat channel archive already exists" do
      sign_in(admin)
      post "/chat/api/channels/#{channel.id}/archives", params: new_topic_params
      expect(response.status).to eq(200)
      expect {
        post "/chat/api/channels/#{channel.id}/archives", params: new_topic_params
      }.not_to change { ChatChannelArchive.count }
    end

    describe "when retrying the archive process" do
      fab!(:channel) { Fabricate(:category_channel, chatable: category, status: :read_only) }
      fab!(:archive) do
        ChatChannelArchive.create!(
          chat_channel: channel,
          destination_topic_title: "test archive topic title",
          archived_by: admin,
          total_messages: 10,
        )
      end

      it "returns error if user is not staff" do
        sign_in(user)
        post "/chat/api/channels/#{channel.id}/archives"
        expect(response.status).to eq(403)
      end

      it "returns a 403 error if the archive is not currently failed" do
        sign_in(admin)
        archive.update!(archive_error: nil)
        post "/chat/api/channels/#{channel.id}/archives"
        expect(response.status).to eq(403)
      end

      it "returns a 403 error if the channel is not read_only" do
        sign_in(admin)
        archive.update!(archive_error: "bad stuff", archived_messages: 1)
        channel.update!(status: "open")
        post "/chat/api/channels/#{channel.id}/archives"
        expect(response.status).to eq(403)
      end

      it "re-enqueues the archive job" do
        sign_in(admin)
        archive.update!(archive_error: "bad stuff", archived_messages: 1)

        expect { post "/chat/api/channels/#{channel.id}/archives" }.to change(
          Jobs::ChatChannelArchive.jobs,
          :size,
        ).by (1)
        expect(response.status).to eq(200)
      end
    end
  end
end
