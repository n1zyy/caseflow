// External Dependencies
import React from 'react';
import PropTypes from 'prop-types';
import { useSelector } from 'react-redux';
import Footer from '@department-of-veterans-affairs/caseflow-frontend-toolkit/components/Footer';

// Local dependencies
import NavigationBar from '@department-of-veterans-affairs/caseflow-frontend-toolkit/components/NavigationBar';
import CaseSearchLink from 'app/components/CaseSearchLink';
import { LOGO_COLORS } from 'app/constants/AppConstants';
import Loadable from 'components/shared/Loadable';

const BaseLayout = ({
  children,
  userDisplayName,
  dropdownUrls,
  applicationUrls,
  feedbackUrl,
  buildDate,
  appName,
  defaultUrl,
}) => {
  const { crumbs } = useSelector(() => ({
    crumbs: [
      {
        breadcrumb: 'Reader',
        path: '/reader/appeal/:vacolsId/documents'
      }
    ]
  }));

  return (
    <React.Fragment>
      <NavigationBar
        wideApp
        appName={appName}
        crumbs={crumbs}
        logoProps={{
          accentColor: LOGO_COLORS[appName.toUpperCase()].ACCENT,
          overlapColor: LOGO_COLORS[appName.toUpperCase()].OVERLAP
        }}
        userDisplayName={userDisplayName}
        dropdownUrls={dropdownUrls}
        applicationUrls={applicationUrls}
        rightNavElement={<CaseSearchLink />}
        defaultUrl={defaultUrl}
        outsideCurrentRouter
      >
        <Loadable spinnerColor={LOGO_COLORS[appName.toUpperCase()].ACCENT}>
          {children}
        </Loadable>
      </NavigationBar>
      <Footer
        wideApp
        appName={appName}
        feedbackUrl={feedbackUrl}
        buildDate={buildDate}
      />
    </React.Fragment>
  );
};

BaseLayout.propTypes = {
  children: PropTypes.element,
  userDisplayName: PropTypes.string,
  dropdownUrls: PropTypes.array,
  applicationUrls: PropTypes.array,
  feedbackUrl: PropTypes.string,
  buildDate: PropTypes.string,
  appName: PropTypes.string,
  defaultUrl: PropTypes.string,
  crumbs: PropTypes.array,
};

export default BaseLayout;