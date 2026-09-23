import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import ErrorBoundary from '../app/error';
import NotFound from '../app/not-found';

describe('Buyer Web Error Boundaries & 404', () => {
  it('renders ErrorBoundary with error message and triggers reset on Try Again', () => {
    const resetMock = vi.fn();
    const testError = new Error('Test catalog crash');

    render(<ErrorBoundary error={testError} reset={resetMock} />);

    expect(screen.getByTestId('buyer-web-error-boundary')).toBeInTheDocument();
    expect(screen.getByText('Something went wrong')).toBeInTheDocument();
    expect(screen.getByText('Test catalog crash')).toBeInTheDocument();

    const retryBtn = screen.getByTestId('error-boundary-retry-btn');
    fireEvent.click(retryBtn);
    expect(resetMock).toHaveBeenCalledTimes(1);

    const homeBtn = screen.getByTestId('error-boundary-home-btn');
    expect(homeBtn).toHaveAttribute('href', '/');
  });

  it('renders NotFound component with navigation to home', () => {
    render(<NotFound />);

    expect(screen.getByTestId('buyer-web-not-found')).toBeInTheDocument();
    expect(screen.getByText('Page Not Found')).toBeInTheDocument();

    const homeBtn = screen.getByTestId('not-found-home-btn');
    expect(homeBtn).toHaveAttribute('href', '/');
  });
});
