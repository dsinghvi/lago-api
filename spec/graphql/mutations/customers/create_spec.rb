# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:stripe_provider) { create(:stripe_provider, organization: organization) }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateCustomerInput!) {
        createCustomer(input: $input) {
          id
          name
          externalId
          city
          country
          paymentProvider
          providerCustomer { id, providerCustomerId }
          currency
          timezone
          canEditAttributes
          invoiceGracePeriod
          billingConfiguration { documentLocale }
        }
      }
    GQL
  end

  it 'creates a customer' do
    stripe_provider

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          name: 'John Doe',
          externalId: 'john_doe_2',
          city: 'London',
          country: 'GB',
          paymentProvider: 'stripe',
          currency: 'EUR',
          providerCustomer: {
            providerCustomerId: 'cu_12345',
          },
          billingConfiguration: {
            documentLocale: 'fr',
          },
        },
      },
    )

    result_data = result['data']['createCustomer']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('John Doe')
      expect(result_data['externalId']).to eq('john_doe_2')
      expect(result_data['city']).to eq('London')
      expect(result_data['country']).to eq('GB')
      expect(result_data['currency']).to eq('EUR')
      expect(result_data['paymentProvider']).to eq('stripe')
      expect(result_data['providerCustomer']['id']).to be_present
      expect(result_data['providerCustomer']['providerCustomerId']).to eq('cu_12345')
      expect(result_data['billingConfiguration']['documentLocale']).to eq('fr')
    end
  end

  context 'with premium feature' do
    around { |test| lago_premium!(&test) }

    it 'creates a customer' do
      stripe_provider

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            name: 'John Doe',
            externalId: 'john_doe_2',
            city: 'London',
            country: 'GB',
            paymentProvider: 'stripe',
            currency: 'EUR',
            timezone: 'TZ_EUROPE_PARIS',
            providerCustomer: {
              providerCustomerId: 'cu_12345',
            },
          },
        },
      )

      result_data = result['data']['createCustomer']

      aggregate_failures do
        expect(result_data['timezone']).to eq('TZ_EUROPE_PARIS')
        expect(result_data['invoiceGracePeriod']).to be_nil
      end
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'John Doe',
            externalId: 'john_doe_2',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            name: 'John Doe',
            externalId: 'john_doe_2',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end

  context 'with validation errors' do
    it 'returns an error with validation messages' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            name: 'John Doe',
            externalId: 'john_doe_2',
            city: 'London',
            country: 'GB',
            vatRate: -12,
          },
        },
      )

      aggregate_failures do
        expect(result['errors']).to be_present

        error = result['errors'].map(&:deep_symbolize_keys).first
        expect(error[:extensions][:code]).to eq('unprocessable_entity')
        expect(error[:extensions][:details][:vatRate]).to be_present
      end
    end
  end
end
