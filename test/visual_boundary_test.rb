# frozen_string_literal: true

require "test_helper"

class RefineryRelayVisualBoundaryTest < ActiveSupport::TestCase
  test "ships no browser assets or visual configuration" do
    assets = Dir[RefineryRelay::Engine.root.join("app/assets/**/*")].select { |path| File.file?(path) }

    assert_empty assets
    refute_respond_to RefineryRelay.configuration, :chat_accent_color
    refute_respond_to RefineryRelay.configuration, :chat_prompt_placeholder
    refute_respond_to RefineryRelay.configuration, :chat_footer_logo_url
  end
end
