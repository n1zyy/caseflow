import React from 'react';
import Modal from '../../components/Modal';
import Alert from '../../components/Alert';
import COPY from '../../../COPY';
import PropTypes from 'prop-types';
import { bindActionCreators } from 'redux';
import { connect } from 'react-redux';
import { withRouter } from 'react-router-dom';

import { highlightInvalidFormItems, resetSaveState } from '../uiReducer/uiActions';

class QueueFlowModal extends React.PureComponent {
  constructor(props) {
    super(props);
    this.state = {
      loading: false
    };
  }

  componentDidMount = () => {
    this.props.highlightInvalidFormItems(false);
  }

  cancelHandler = () => this.props.onCancel ? this.props.onCancel() : this.props.history.goBack();

  closeHandler = () => this.props.history.replace(this.props.pathAfterSubmit);

  setLoading = (loading) => this.setState({ loading });

  submit = () => {
    const { validateForm } = this.props;

    if (validateForm && !validateForm()) {
      return this.props.highlightInvalidFormItems(true);
    }

    this.props.highlightInvalidFormItems(false);
    this.setState({ loading: true });

    this.props.
      submit().
      then(() => {
        // Not every component that uses queue flow modal sets saveSuccessful, so we may have a null here. Until every
        // component sets saveSuccessful on success or failure, this cannot be updated to saveSuccessful === true
        if (this.props.saveSuccessful !== false) {
          this.closeHandler();
        }
      }).
      finally(() => {
        this.props.resetSaveState();
        this.setState({ loading: false });
      });
  };

  render = () => {
    const { title, button, children, error, success, submitDisabled } = this.props;

    return (
      <Modal
        title={title}
        buttons={[
          {
            classNames: ['usa-button', 'cf-btn-link'],
            name: COPY.MODAL_CANCEL_BUTTON,
            onClick: this.cancelHandler
          },
          {
            classNames: ['usa-button-secondary', 'usa-button-hover', 'usa-button-warning'],
            name: button,
            disabled: submitDisabled,
            loading: this.state.loading,
            onClick: this.submit
          }
        ]}
        closeHandler={this.cancelHandler}
      >
        {error && <Alert title={error.title} type="error">{error.detail}</Alert>}
        {success && <Alert title={success.title} type="success">{success.detail}</Alert>}
        {children}
      </Modal>
    );
  };
}

QueueFlowModal.defaultProps = {
  button: COPY.MODAL_SUBMIT_BUTTON,
  pathAfterSubmit: '/queue',
  submitDisabled: false,
  title: ''
};

QueueFlowModal.propTypes = {
  children: PropTypes.node,
  highlightInvalidFormItems: PropTypes.func,
  history: PropTypes.object,
  title: PropTypes.string,
  button: PropTypes.string,
  onCancel: PropTypes.func,
  pathAfterSubmit: PropTypes.string,
  // submit should return a promise on which .then() can be called
  submit: PropTypes.func,
  submitDisabled: PropTypes.bool,
  validateForm: PropTypes.func,
  saveSuccessful: PropTypes.bool,
  success: PropTypes.object,
  error: PropTypes.object,
  resetSaveState: PropTypes.func
};

const mapStateToProps = (state) => ({
  saveSuccessful: state.ui.saveState.saveSuccessful,
  success: state.ui.messages.success,
  error: state.ui.messages.error
});

const mapDispatchToProps = (dispatch) =>
  bindActionCreators(
    {
      highlightInvalidFormItems,
      resetSaveState
    },
    dispatch
  );

export default withRouter(
  connect(
    mapStateToProps,
    mapDispatchToProps
  )(QueueFlowModal)
);
