import React from 'react';
import Alert from '../../components/Alert';

const AlreadyCertified = () => {
  return <div>
    <Alert
      title="Appeal has already been certified"
      type="info">
      This case has already been certified to the Board.
    </Alert>

    <div className="cf-app-segment cf-app-segment--alt">
      <h2>Appeal has already been certified</h2>

      <p>
        This case has already been certified to the Board. If this case is a remand
        being re-certified to the Board, Caseflow is not currently able to
        process remand cases.
      </p>
    </div>
  </div>;
};

export default AlreadyCertified;
