import React from 'react';
import PropTypes from 'prop-types';
import { BrowserRouter, Switch } from 'react-router-dom';
import { detect } from 'detect-browser';
import NavigationBar from '../components/NavigationBar';
import Footer from '@department-of-veterans-affairs/caseflow-frontend-toolkit/components/Footer';
import AppFrame from '../components/AppFrame';
import PageRoute from '../components/PageRoute';
import { LOGO_COLORS } from '../constants/AppConstants';
import BuildScheduleContainer from './containers/BuildScheduleContainer';
import BuildScheduleUploadContainer from './containers/BuildScheduleUploadContainer';
import ReviewAssignmentsContainer from './containers/ReviewAssignmentsContainer';
import ListScheduleContainer from './containers/ListScheduleContainer';
import AssignHearingsContainer from './containers/AssignHearingsContainer';
import DailyDocketContainer from './containers/DailyDocketContainer';
import HearingDetailsContainer from './containers/DetailsContainer';
import HearingWorksheetContainer from '../hearings/containers/HearingWorksheetContainer';
import ScrollToTop from '../components/ScrollToTop';
import UnsupportedBrowserBanner from '../components/UnsupportedBrowserBanner';

export default class HearingsApp extends React.PureComponent {
  userPermissionProps = () => {
    const {
      userRoleAssign,
      userRoleBuild,
      userRoleView,
      userRoleVso,
      userRoleHearingPrep,
      userInHearingsOrganization
    } = this.props;

    return {
      userRoleAssign,
      userRoleBuild,
      userRoleView,
      userRoleVso,
      userRoleHearingPrep,
      userInHearingsOrganization
    };
  };

  propsForAssignHearingsContainer = () => {
    const {
      userId,
      userCssId
    } = this.props;

    return {
      userId,
      userCssId
    };
  };

  routeForListScheduleContainer = () => <ListScheduleContainer {...this.userPermissionProps()} />;
  routeForAssignHearingsContainer = () => <AssignHearingsContainer {...this.propsForAssignHearingsContainer()} />
  routeForDailyDocket = () => <DailyDocketContainer user={this.userPermissionProps()} />;
  routeForHearingDetails = ({ match: { params }, history }) =>
    <HearingDetailsContainer hearingId={params.hearingId} history={history} {...this.userPermissionProps()} />;
  routeForHearingWorksheet = (print) => ({ match: { params } }) =>
    detect().name === 'chrome' ? <HearingWorksheetContainer print={print} hearingId={params.hearingId} /> :
      <UnsupportedBrowserBanner appName="Hearings" />;

  render = () => <BrowserRouter basename="/hearings">
    <Switch>
      <PageRoute
        exact
        path="/:hearingId/worksheet/print"
        title="Hearing Worksheet"
        render={this.routeForHearingWorksheet(true)}
      />
      <NavigationBar
        wideApp
        defaultUrl="/schedule"
        userDisplayName={this.props.userDisplayName}
        dropdownUrls={this.props.dropdownUrls}
        applicationUrls={this.props.applicationUrls}
        logoProps={{
          overlapColor: LOGO_COLORS.HEARINGS.OVERLAP,
          accentColor: LOGO_COLORS.HEARINGS.ACCENT
        }}
        appName="Hearings">
        <AppFrame wideApp>
          <ScrollToTop />
          <div className="cf-wide-app">
            <PageRoute
              exact
              path="/:hearingId/details"
              title="Hearing Details"
              render={this.routeForHearingDetails}
            />
            <PageRoute
              exact
              path="/:hearingId/worksheet"
              title="Hearing Worksheet"
              render={this.routeForHearingWorksheet(false)}
            />
            <PageRoute
              exact
              path="/schedule"
              title="Scheduled Hearings"
              render={this.routeForListScheduleContainer}
            />
            <PageRoute
              exact
              path="/schedule/docket/:hearingDayId"
              title="Daily Docket"
              render={this.routeForDailyDocket}
            />
            <PageRoute
              exact
              path="/schedule/build"
              title="Caseflow Hearings"
              breadcrumb="Build"
              component={BuildScheduleContainer}
            />
            <PageRoute
              exact
              path="/schedule/build/upload"
              title="Upload Files"
              breadcrumb="Upload"
              component={BuildScheduleUploadContainer}
            />
            <PageRoute
              exact
              path="/schedule/build/upload/:schedulePeriodId"
              title="Review Assignments"
              breadcrumb="Review"
              component={ReviewAssignmentsContainer}
            />
            <PageRoute
              exact
              path="/schedule/assign"
              title="Assign Hearings"
              breadcrumb="Assign"
              component={this.routeForAssignHearingsContainer}
            />
          </div>
        </AppFrame>
        <Footer
          wideApp
          appName="Hearings"
          feedbackUrl={this.props.feedbackUrl}
          buildDate={this.props.buildDate}
        />
      </NavigationBar>
    </Switch>
  </BrowserRouter>;
}

HearingsApp.propTypes = {
  userDisplayName: PropTypes.string,
  dropdownUrls: PropTypes.array,
  applicationUrls: PropTypes.array,
  feedbackUrl: PropTypes.string.isRequired,
  buildDate: PropTypes.string,
  userRoleAssign: PropTypes.bool,
  userRoleBuild: PropTypes.bool,
  userRoleView: PropTypes.bool,
  userRoleVso: PropTypes.bool,
  userRoleHearingPrep: PropTypes.bool,
  userInHearingsOrganization: PropTypes.bool,
  userRole: PropTypes.string,
  userId: PropTypes.number,
  userCssId: PropTypes.string
};