# frozen_string_literal: true

describe ControllerSchema do
  let(:params) { ActionController::Parameters.new(params_hash) }
  let(:schema) do
    ControllerSchema.json do |schema|
      schema.integer :id
      schema.string :name, nullable: true
      schema.date :date_of_birth, optional: true
    end
  end

  shared_context "nested_schema" do
    let(:schema) do
      ControllerSchema.json do |schema|
        schema.nested :inner,
                      optional: true,
                      nullable: true do |nested|
                        nested.string :field, optional: false, nullable: false
                      end
      end
    end
  end

  shared_context "array_schema" do
    let(:schema) do
      ControllerSchema.json do |schema|
        schema.integer :ids, array: true, nullable: true
      end
    end
  end

  describe "#remove_unknown_keys" do
    subject do
      schema.remove_unknown_keys(params, path_params: { known: "foo" })
    end

    context "when unknown params are included" do
      let(:params_hash) { { id: 123, name: "value", known: "foo", unknown: "bar" } }

      it "removes unknown params" do
        subject
        expect(params).to include(:id, :name, :known)
        expect(params).not_to include(:unknown)
      end
    end

    context "for nested schema" do
      include_context "nested_schema"

      context "when unknown params are included in nested field" do
        let(:params_hash) { { inner: { field: "hello", not_field: 123 } } }

        it "removes unknown params" do
          subject
          expect(params).to include(:inner)
          expect(params[:inner]).to include(:field)
          expect(params[:inner]).not_to include(:not_field)
        end
      end
    end
  end

  describe "#validate" do
    subject { schema.validate(params) }

    context "when a required param is missing" do
      let(:params_hash) { { name: "foo" } }

      it "returns a failure result" do
        expect(subject.failure?).to be_truthy
      end
    end

    context "for nested schema with nullable field" do
      include_context "nested_schema"

      context "when nested field is null" do
        let(:params_hash) { { inner: nil } }

        it "returns a success" do
          expect(subject.failure?).to be_falsey
        end
      end

      context "when nested field is not included" do
        let(:params_hash) { {} }

        it "returns a success" do
          expect(subject.failure?).to be_falsey
        end
      end

      context "when nested field is not valid" do
        let(:params_hash) { { inner: { field: nil } } }

        it "returns a failure" do
          expect(subject.failure?).to be_truthy
        end
      end
    end

    context "for array schema" do
      include_context "array_schema"

      context "when ids is empty" do
        let(:params_hash) { { ids: [] } }

        it "returns a success" do
          expect(subject.failure?).to be_falsey
        end
      end

      context "when ids contains nil" do
        let(:params_hash) { { ids: [nil] } }

        it "returns a success" do
          expect(subject.failure?).to be_truthy
        end
      end

      context "when array field is nil" do
        let(:params_hash) { { ids: nil } }

        it "returns a success" do
          expect(subject.failure?).to be_falsey
        end
      end
    end
  end
end
