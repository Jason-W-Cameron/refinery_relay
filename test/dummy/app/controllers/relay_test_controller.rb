# frozen_string_literal: true

class RelayTestController < ApplicationController
  layout "relay_test"

  def show
    @pod = Refinery::Pods::Pod.includes(:pod_items).find(params[:pod_id])
  end
end
