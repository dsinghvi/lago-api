# frozen_string_literal: true

class Coupon < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  has_many :applied_coupons
  has_many :customers, through: :applied_coupons
  has_many :coupon_plans
  has_many :plans, through: :coupon_plans

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  EXPIRATION_TYPES = [
    :no_expiration,
    :time_limit,
  ].freeze

  COUPON_TYPES = [
    :fixed_amount,
    :percentage,
  ].freeze

  FREQUENCIES = [
    :once,
    :recurring,
    :forever,
  ].freeze

  enum status: STATUSES
  enum expiration: EXPIRATION_TYPES
  enum coupon_type: COUPON_TYPES
  enum frequency: FREQUENCIES

  monetize :amount_cents, disable_validation: true, allow_nil: true

  validates :name, presence: true
  validates :code, uniqueness: { conditions: -> { where(deleted_at: nil) }, scope: :organization_id }

  validates :amount_cents, numericality: { greater_than: 0 }, allow_nil: true
  validates :amount_currency, inclusion: { in: currency_list }, allow_nil: true

  default_scope -> { kept }
  scope :order_by_status_and_expiration,
        lambda {
          order(
            Arel.sql(
              [
                'coupons.status ASC',
                'coupons.expiration ASC',
                'coupons.expiration_at ASC',
              ].join(', '),
            ),
          )
        }

  scope :expired, -> { where('coupons.expiration_at::timestamp(0) < ?', Time.current) }

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end
end
