import './style.scss';

import { EuclidData, Book, BookNode, EUCLID_DATA } from './data';
import { Imogene as $_, ImogeneArray } from '../Imogene/Imogene';

import {MDCRipple} from '@material/ripple';
import showdown from 'showdown';
import DOMPurify from 'dompurify';

/**
 * Cleans up a path string
 * @param {string} path The path to clean up
 * @returns The cleaned up path string
 */
function cleanPath(path) {
    return path;//.replace('/', '/Euclid');
}
/**
 * Reverse-Cleans a path string
 * @param {string} path The path to reverse-clean
 * @returns The reverse-cleaned up path string
 */
function reverseCleanPath(path) {
    return path;//.replace('/Euclid', '/');
}

/**
 * Get the Book Node that matches the given page, from a top node
 * @param {string} searchBy The page to find a match for
 * @param {BookNode|Book} obj The node to search for matches within
 * @returns {BookNode|Book} The matching book node, or null if not found
 */
function getMatchingPage(searchBy, obj) {
    if (obj.page && obj.page === searchBy) {
        return obj;
    }
    else if ('children' in obj) {
        return obj.children.reduce((prev, curr, index) => {
            if (prev != null)
                return prev;
            let tryMatch = getMatchingPage(searchBy, curr);
            if (tryMatch !== null)
                return tryMatch;
            return null;
        }, null);
    }
    return null;
}

/**
 * Get the Book Node that matches a given page, from the Book
 * @param {string} searchBy The page to find a match for
 * @param {Book} curr The book to search within
 * @returns {BookNode|Book} The matching book node, or null if not found
 */
function matchingPageFromBook(searchBy, curr) {
    let match = getMatchingPage(searchBy, curr);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.definitions);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.postulates);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.common_notions);
    if (match !== null)
        return match;
    match = getMatchingPage(searchBy, curr.propositions);
    if (match !== null)
        return match;

    return null;
}

/**
 * Find a matching page within the Euclid Data
 * @param {string} searchBy The page to find a match for
 * @returns {BookNode|Book|EuclidData} The matching book node, or null if not found
 */
function findMatchingPage(searchBy) {
    if (searchBy === EUCLID_DATA.page) {
        return EUCLID_DATA;
    }

    let match = EUCLID_DATA.books.reduce((prev, curr, index) => {
        if (prev !== null)
            return prev;
        return matchingPageFromBook(searchBy, curr);
    }, null);

    return match;
}

/**
 * Collect breadcrumbs for a page, starting from a given root
 * @param {string} forPage The page to get the breadcrumbs for
 * @param {BookNode|Book} obj The starting root to collect breadcrumbs for
 * @returns {(BookNode|Book)[]} Array of Books and Book Nodes representing the page hierarchy
 */
function breadcrumbPage(forPage, obj) {
    if (obj.page === forPage) {
        return [obj];
    }
    else if ('children' in obj) {
        return obj.children.reduce((arr, child) => {
            if (arr.length > 0)
                return arr;

            let newCrumbs = breadcrumbPage(forPage, child);
            if (newCrumbs.length > 0)
                return [obj, ...newCrumbs];
            return [];
        }, []);
    }
    return [];
}

/**
 * Collect the current page hierarchy to create breadcrumbs for
 * @param {string} forPage The page to get breadcrumbs for
 * @returns {(BookNode|Book)[]} Array of Books and BookNodes representing the current page hierarchy
 */
function breadcrumb(forPage) {
    return EUCLID_DATA.books.reduce((arr, book) => {
        if (arr.length > 1)
            return arr;

        if (book.page === forPage) {
            arr.push(book);
        }
        else {
            let crumbs = breadcrumbPage(forPage, book.definitions)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.postulates)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.common_notions)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
            crumbs = breadcrumbPage(forPage, book.propositions)
            if (crumbs.length > 0) {
                arr.push(book, ...crumbs);
                return arr;
            }
        }
        return arr;
    }, [EUCLID_DATA]);
}


/**
 * Load the current page into view
 */
function loadCurrentPage() {
    let currentPage = cleanPath(`${window.location.pathname}`);
    if (currentPage.slice(-1) === '/') {
        currentPage = currentPage + "index.html"
    }
    let page = findMatchingPage(currentPage);

    let article = $_.find("#main-article");

    let text = `# ${page.title}\n\n${page.head}`;
    if (page.animation2d)
    {
        text = `${text}\n\n## 2D Animation\n\n[![${page.title} 2D](${page.animation2d})](${page.animation2d})`
    }
    if (page.animation3d)
    {
        text = `${text}\n\n## 3D Animation\n\n[![${page.title} 3D](${page.animation3d})](${page.animation3d})`
    }
    const html = DOMPurify.sanitize(new showdown.Converter().makeHtml(text));
    article.empty();
    article.setProperties({ innerHTML: html });
}

/**
 * Build a sidebar list from a given Book or BookNode structure
 * @param {BookNode|Book} obj The book or node to build a sidebar list for
 * @param {string} currentPage The current page the user is viewing
 * @param {number} num The number of the current item on the list
 * @returns {ImogeneArray} The constructed list item
 */
function generateSideBarListFrom(obj, currentPage, num) {
    let hasChildren = ('children' in obj);
    let childrenSplitDef = hasChildren && ('splitdef' in obj) && (obj.splitdef == true);
    let matchPage = getMatchingPage(currentPage, obj);
    let listItem = $_.make('li', {
        class: `${matchPage === null || matchPage === undefined ? (childrenSplitDef ? '' : 'collapsed') : 'on_page'} ` +
                `${hasChildren && !childrenSplitDef ? "with_children" : "no_children"}`
    });
    let linkHref = reverseCleanPath(obj.page);
    let linkElement = $_.make('a',
        {
            href: matchPage === obj ? undefined : linkHref,
            class: 'nav_link'
        },
        `${num ? num + '. ' : ''}${obj.title}`);

    obj.link_element = linkElement;
    obj.listitem_element = listItem;

    if (hasChildren) {
        if (!childrenSplitDef) {
            linkElement.emptyAndReplace($_.make('span', {
                class: "material-symbols-outlined collapse-marker",
                innerHTML: "expand_more"
            }), obj.title);
        }
        listItem.appendChildren(
            linkElement);

        let subList = $_.make('ol',
            {
                class: `nav-ord-list${childrenSplitDef ? ' splitdef' : ''}`
            },
            ...(obj.children.map((child, index) =>
                generateSideBarListFrom(child, currentPage,
                    childrenSplitDef ? (index + 10).toString(26).toLowerCase() : index + 1))));
        listItem.appendChildren(subList);
        obj.sublist_element = subList;
    }
    else {
        listItem.appendChildren(linkElement);
    }

    return listItem;
}

/**
 * Load the sidebar based on the EUCLID_DATA structure
 */
function loadSideBar() {
    let currentPage = cleanPath(`${window.location.pathname}`);
    if (currentPage.slice(-1) === '/') {
        currentPage = currentPage + "index.html"
    }

    let navlist = $_.find('#side-navlist');

    navlist.empty();

    navlist.appendChildren(
        $_.make('li', { class: `home_item ${currentPage === EUCLID_DATA.page ? 'on_page' : ''}` },
                ['a',
                    {
                        href: currentPage === EUCLID_DATA.page ? undefined : reverseCleanPath(EUCLID_DATA.page),
                        class: 'nav_link'
                    },
                    ['span', { class: 'material-symbols-outlined home_icon' }, 'home'],
                    EUCLID_DATA.title]));


    EUCLID_DATA.books.forEach(book => {
        let matchPage = matchingPageFromBook(currentPage, book);

        let childEl = $_.make('li', { class: matchPage === null || matchPage === undefined ? "collapsed" : 'on_page' });
        let linkElement = $_.make('a',
                                    {
                                        href: matchPage === book ? undefined : reverseCleanPath(book.page),
                                        class: 'nav_link'
                                    },
                                    book.title);
        let subList = $_.make('ul', { class: 'nav-hier-list' },
                                generateSideBarListFrom(book.definitions, currentPage),
                                generateSideBarListFrom(book.postulates, currentPage),
                                generateSideBarListFrom(book.common_notions, currentPage),
                                generateSideBarListFrom(book.propositions, currentPage));
        linkElement.emptyAndReplace(
            $_.make('span',
                {
                    class: "material-symbols-outlined collapse-marker",
                    innerHTML: "expand_more"
                }), book.title);
        childEl.appendChildren(
            linkElement,
            subList);
        navlist.appendChildren(childEl);

        book.link_element = linkElement;
        book.listitem_element = childEl;
        book.sublist_element = subList;
    });
}

/**
 * Refresh the selection based on the current page
 * @param {BookNode} obj The node object to refresh selection for
 * @param {string} currentPage The current page located on
 */
function refreshPageSelection(obj, currentPage) {
    let matchPage = getMatchingPage(cleanPath(currentPage), obj);
    obj.listitem_element.setClassList({
        on_page: !!matchPage,
        collapsed: matchPage !== obj && obj.listitem_element[0].classList.contains('collapsed')
    });
    obj.link_element.setProperties({ href: matchPage === obj ? undefined : reverseCleanPath(obj.page)});

    if ('children' in obj) {
        obj.children.forEach(child => refreshPageSelection(child, currentPage));
    }
}

/**
 * Update the breadcrumbs to respect a given path
 * @param {string} pathname The current path to update the breadcrumbs to
 */
function updateBreadcrumbs(pathname) {
    let crumbs = breadcrumb(cleanPath(pathname));
    let crumbsList = $_.find('ol#breadcrumb-list');
    crumbsList.emptyAndReplace(
        ...(crumbs.map(crumb =>
            $_.make('li', ['a', { href: reverseCleanPath(crumb.page) }, crumb.title]))));
}

/**
 * Update the view to a given path
 * @param {string} pathname The current path to update the view to
 */
function refreshTheView(pathname) {
    loadCurrentPage();

    let home_item = $_.find('.home_item');
    let home_link = home_item.find('a');
    home_item.setClassList({ on_page: (cleanPath(pathname) === EUCLID_DATA.page) });
    home_link.setProperties({
        href: cleanPath(pathname) === EUCLID_DATA.page ?
            undefined : reverseCleanPath(EUCLID_DATA.page)
    });
    EUCLID_DATA.books.forEach(book => {
        let matchPage = matchingPageFromBook(cleanPath(pathname), book);
        book.listitem_element.setClassList({
            on_page: !!matchPage,
            collapsed: matchPage !== book && book.listitem_element[0].classList.contains('collapsed')
        });
        book.link_element.setProperties({ href: matchPage === book ? undefined : reverseCleanPath(book.page)});

        refreshPageSelection(book.definitions, pathname);
        refreshPageSelection(book.postulates, pathname);
        refreshPageSelection(book.common_notions, pathname);
        refreshPageSelection(book.propositions, pathname);
    });

    // Load breadcrumbs
    updateBreadcrumbs(pathname);
}

/**
 * Event that is run when clicked somewere in the document
 * @param {MouseEvent} e Event description from DOM
 */
function onDocumentClick(e) {
    let link = e.target.closest('a');
    if (link) {
        let pathname = cleanPath(link.pathname);
        if (pathname === '' || pathname === undefined || pathname === null) {
            pathname = cleanPath(window.location.pathname);
            let match = findMatchingPage(pathname);
            if (match) {
                match.listitem_element.setClassList({
                    collapsed: !match.listitem_element[0].classList.contains('collapsed')
                                && !match.listitem_element[0].classList.contains('no_children')
                });
            }
        }
        else if (e.target.classList.contains('collapse-marker')) {
            e.preventDefault();
            let match = findMatchingPage(pathname);
            if (match) {
                match.listitem_element.setClassList({
                    collapsed: !match.listitem_element[0].classList.contains('collapsed')
                                && !match.listitem_element[0].classList.contains('no_children')
                });
            }
        }
        else if (pathname.match(/\.(png|jpe?g|gif|svg)$/)) {
            e.preventDefault();
            let closeButton = $_.make('div', { class: 'material-symbols-outlined overlay-x' }, 'close');
            let sect = $_.make('section', { class: 'image-overlay' },
                                ['img', { src: pathname }], closeButton)

            closeButton.addEvents({
                click: e => {
                    sect[0].remove();
                }
            });
            $_.appendChildren(document.body, sect);
        }
        else {
            let match = findMatchingPage(pathname);
            if (match !== null && match !== undefined) {
                e.preventDefault();

                history.pushState({ from: `${window.location.pathname}`, to: `${pathname}` }, "", link.pathname);

                refreshTheView(link.pathname);
            }
        }
    }
}



/**
 * Initialize everything, build the sidebar, and go to the appropriate, matching page
 */
$_.runOnLoad(() => {
    loadSideBar();

    loadCurrentPage();

    updateBreadcrumbs(cleanPath(window.location.pathname));


    document.addEventListener("click", onDocumentClick);

    window.addEventListener("popstate", e => {
        e.preventDefault();
        refreshTheView(window.location.pathname);
    });

    let sidebar = $_.find('#sidebar');
    let sidebarCollapser = $_.find('#sidebar-collapser');
    sidebarCollapser.ripple = new MDCRipple(sidebarCollapser[0]);
    sidebarCollapser.addEvents({
        click: e => {
            sidebar.setClassList({ collapsed: !sidebar[0].classList.contains('collapsed') });
        }
    });

    const portrait = window.matchMedia("(orientation: portrait)").matches;
    sidebar.setClassList({ collapsed: portrait });
});
