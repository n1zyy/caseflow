import React from 'react';
import { shallow } from 'enzyme';

import { ScheduleVeteranForm } from 'app/hearings/components/ScheduleVeteranForm';
import { ReadOnly } from 'app/hearings/components/details/ReadOnly';
import { amaAppeal, defaultHearing, virtualHearing } from 'test/data';
import { queueWrapper, queueStore } from 'test/data/stores/queueStore';
import HearingTypeDropdown from 'app/hearings/components/details/HearingTypeDropdown';
import {
  HearingDateDropdown,
  RegionalOfficeDropdown,
  AppealHearingLocationsDropdown,
} from 'app/components/DataDropdowns';
import { AddressLine } from 'app/hearings/components/details/Address';
import { HearingTime } from 'app/hearings/components/modalForms/HearingTime';
import { AppellantSection } from 'app/hearings/components/VirtualHearings/AppellantSection';
import { RepresentativeSection } from 'app/hearings/components/VirtualHearings/RepresentativeSection';

// Set the spies
const changeSpy = jest.fn();
const submitSpy = jest.fn();
const cancelSpy = jest.fn();

describe('ScheduleVeteranForm', () => {
  test('Matches snapshot with default props', () => {
    // Render the address component
    const scheduleVeteran = shallow(
      <ScheduleVeteranForm
        goBack={cancelSpy}
        submit={submitSpy}
        onChange={changeSpy}
        appeal={amaAppeal}
        hearing={defaultHearing}
      />,
      {
        wrappingComponent: queueWrapper,
      }
    );

    // Assertions
    expect(scheduleVeteran.find(ReadOnly)).toHaveLength(1);
    expect(scheduleVeteran.find(ReadOnly).prop('text')).toMatchObject(<AddressLine />);
    expect(scheduleVeteran.find(HearingTypeDropdown)).toHaveLength(1);
    expect(scheduleVeteran.find(RegionalOfficeDropdown)).toHaveLength(1);
    expect(scheduleVeteran).toMatchSnapshot();
  });

  test('Displays hearing form when regional office is selected', () => {
    // Render the address component
    const scheduleVeteran = shallow(
      <ScheduleVeteranForm
        goBack={cancelSpy}
        submit={submitSpy}
        onChange={changeSpy}
        appeal={{
          ...amaAppeal,
          regionalOffice: defaultHearing.regionalOfficeKey,
        }}
        hearing={defaultHearing}
      />,
      {
        wrappingComponent: queueWrapper,
      }
    );

    // Assertions
    expect(scheduleVeteran.find(AppealHearingLocationsDropdown)).toHaveLength(1);
    expect(scheduleVeteran.find(HearingDateDropdown)).toHaveLength(1);
    expect(scheduleVeteran.find(HearingTime)).toHaveLength(1);
    expect(scheduleVeteran).toMatchSnapshot();
  });

  test('Displays Virtual Hearing form fields when type is changed to Virtual', () => {
    // Render the address component
    const scheduleVeteran = shallow(
      <ScheduleVeteranForm
        virtual
        goBack={cancelSpy}
        submit={submitSpy}
        onChange={changeSpy}
        appeal={{
          ...amaAppeal,
          regionalOffice: defaultHearing.regionalOfficeKey,
        }}
        hearing={{
          ...defaultHearing,
          virtualHearing: virtualHearing.virtualHearing
        }}
      />,
      {
        wrappingComponent: queueWrapper,
      }
    );

    expect(scheduleVeteran.find(AppellantSection)).toHaveLength(1);
    expect(scheduleVeteran.find(RepresentativeSection)).toHaveLength(1);
    expect(scheduleVeteran).toMatchSnapshot();
  });

  test('Displays error messages when errors are present', () => {
    // Setup the test
    const error = 'Please select hearing day';

    // Render the address component
    const scheduleVeteran = shallow(
      <ScheduleVeteranForm
        errors={{ hearingDay: error }}
        goBack={cancelSpy}
        submit={submitSpy}
        onChange={changeSpy}
        appeal={{
          ...amaAppeal,
          regionalOffice: defaultHearing.regionalOfficeKey,
        }}
        hearing={defaultHearing}
      />,
      {
        wrappingComponent: queueWrapper,
      }
    );

    // Assertions
    expect(scheduleVeteran.find(HearingDateDropdown).prop('errorMessage')).toEqual(error);
    expect(scheduleVeteran).toMatchSnapshot();
  });
});
